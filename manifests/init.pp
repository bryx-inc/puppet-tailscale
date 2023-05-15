# @summary
#
# Installs tailscale and adds to the network via tailscale up
#
# @param $auth_key 
#   the authorization key either onetime or multi-use
#
# @param $base_pkg_url
#   the base url of where to get the package
#
# @param $up_options
#   the options to use when running tailscale up for the first time
#
# @param $use_node_encrypt
#   use node encrypt when running tailscale up.  This requires a puppetserver and node encrypt
# @example
#   include tailscale
class tailscale (
  Variant[String, Sensitive[String]] $auth_key,
  Stdlib::HttpUrl $base_pkg_url,
  Boolean $manage_package = true,
  Boolean $manage_service = true,
  Boolean $manage_package_repository = true,
  Hash $up_options = {},
  Boolean $use_node_encrypt = false
) {
  if $manage_package_repository {
    case $facts['os']['family'] {
      'Debian': {
        if (($facts['os']['distro']['id'] == 'Debian' and $facts['os']['release']['major'] >= '11')
        or ($facts['os']['distro']['id'] == 'Ubuntu' and $facts['os']['release']['major'] >= '20.04')) {
          $key_source = "https://pkgs.tailscale.com/stable/${downcase($facts['os']['distro']['id'])}/${facts['os']['distro']['codename']}.noarmor.gpg"
        } else {
          $key_source = "https://pkgs.tailscale.com/stable/${downcase($facts['os']['distro']['id'])}/${facts['os']['distro']['codename']}.asc"
        }
        apt::source { 'tailscale':
          comment  => "Tailscale packages for ${facts['os']['distro']['id']} ${facts['os']['distro']['codename']}",
          location => "https://pkgs.tailscale.com/stable/${downcase($facts['os']['distro']['id'])}",
          release  => $facts['os']['distro']['codename'],
          repos    => 'main',
          key      => {
            'id'     => '2596A99EAAB33821893C0A79458CA832957F5868',
            'source' => $key_source,
          },
          before   => Package['tailscale'],
          notify   => Exec['apt_update'],
        }
      }
      'RedHat': {
        yumrepo { 'tailscale-stable':
          ensure   => 'present',
          descr    => 'Tailscale stable',
          baseurl  => "${base_pkg_url}/${facts[operatingsystemmajrelease]}/\$basearch",
          gpgkey   => "${base_pkg_url}/${facts[operatingsystemmajrelease]}/repo.gpg",
          enabled  => '1',
          gpgcheck => '0',
          target   => '/etc/yum.repo.d/tailscale-stable.repo',
        }
      }
      default: {
        fail('OS not support for tailscale')
      }
    }
  }
  if $manage_package {
    case $facts['os']['family'] {
      'Debian': {
        package { 'tailscale':
          ensure  => latest,
          require => Exec['apt_update'],
        }
      }
      default: {
        package { 'tailscale':
          ensure  => latest,
        }
      }
    }
  }
  if ($::facts.dig('os', 'distro', 'id') == 'Pop') {
    $service_provider = 'systemd'
  } else {
    $service_provider = undef
  }
  if $manage_service {
    service { 'tailscaled':
      ensure   => running,
      enable   => true,
      provider => $service_provider,
      require  => [Package['tailscale']],
    }
  }

  $up_cli_options =  $up_options.map |$key, $value| { "--${key}=${value}" }.join(' ')

  if $use_node_encrypt {
    # uses node encrypt to unwrap the sensitive value then encrypts it
    # on the command line during execution the value is decrypted and never exposed to logs since the value
    # is temporary only exposed in a env variable
    $ts_args = "--authkey=\$(puppet node decrypt --env SECRET) ${up_cli_options}".rstrip
    $env = ["SECRET=${node_encrypt($auth_key.unwrap)}"]
  } else {
    $ts_args = "--authkey=\$SECRET ${up_cli_options}".rstrip
    $env = ["SECRET=${auth_key.unwrap}"]
  }
  exec { 'run tailscale up':
    command     => "tailscale up ${ts_args}",
    provider    => shell,
    environment => $env,
    unless      => 'test $(tailscale status | wc -l) -gt 1',
    require     => Service['tailscaled'],
  }
  exec { 'run tailscale set':
    command     => "tailscale set ${up_cli_options}",
    provider    => shell,
    onlyif      => 'test $(tailscale status | wc -l) -gt 1',
    require     => Service['tailscaled'],
  }
}
