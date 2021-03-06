{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.lighttpd.collectd-graph-panel;

  phpfpmSocketName = "/run/phpfpm/collectd-graph-panel.sock";

  collectd-graph-panel-1 =
    pkgs.stdenv.mkDerivation rec {
      name = "collectd-graph-panel-${version}";
      version = "1";
      src = pkgs.fetchzip {
        name = "${name}-src";
        url = "https://github.com/pommi/CGP/archive/v${version}.tar.gz";
        sha256 = "1inifs9rapjyjx43046lcjsz2pvnd0n7dihk07577ld2xw5gydv9";
      };
      buildCommand = ''
        mkdir -p "$out"
        cp -r "$src"/. "$out"
        chmod +w "$out"/conf
        cat > "$out"/conf/config.local.php << EOF
        <?php
        \$CONFIG['datadir'] = '/var/lib/collectd';
        \$CONFIG['rrdtool'] = '${pkgs.rrdtool}/bin/rrdtool';
        \$CONFIG['graph_type'] = 'canvas';
        \$CONFIG['typesdb'] = '${pkgs.collectd}/share/collectd/types.db';
        # Plugins to show on the overview page
        \$CONFIG['overview'] = array('load', 'cpu', 'memory', 'swap', 'sensors', 'uptime');
        ?>
        EOF
      '';
    };
in
{
  options.services.lighttpd.collectd-graph-panel = {

    enable = mkEnableOption "Collectd Graph Panel in lighttpd";

    package = mkOption {
      type = types.package;
      default = collectd-graph-panel-1;
      defaultText = "collectd-graph-panel-1";
      description = "Collectd Graph Panel package to use.";
    };

    urlPrefix = mkOption {
      type = types.str;
      default = "/collectd";
      example = "/";
      description = ''
        The prefix below the web server root URL to serve Collectd Graph Panel.
      '';
    };

    vhostsPattern = mkOption {
      type = types.str;
      default = ".*";
      example = "(myserver1.example|myserver2.example)";
      description = ''
        A virtual host regexp filter. Change it if you want Collectd Graph
        Panel to only be served from some host names, instead of all.
      '';
    };

  };

  config = mkIf (config.services.lighttpd.enable && cfg.enable) {

    services.lighttpd = {
      enableModules = [ "mod_alias" "mod_fastcgi" ];
      extraConfig = ''
        $HTTP["host"] =~ "${cfg.vhostsPattern}" {
            alias.url += ( "${cfg.urlPrefix}" => "${cfg.package}/" )
            $HTTP["url"] =~ "^${cfg.urlPrefix}" {
                index-file.names += ( "index.php" )
                fastcgi.server = (
                    ".php" => (
                        "phpfpm-collectd-graph-panel" => (
                            "socket" => "${phpfpmSocketName}",
                        )
                    )
                )
            }
        }
      '';
    };

    services.phpfpm.poolConfigs = {
      collectd-graph-panel = ''
        listen = ${phpfpmSocketName}
        listen.group = lighttpd
        user = lighttpd
        group = lighttpd
        pm = dynamic
        pm.max_children = 75
        pm.start_servers = 10
        pm.min_spare_servers = 5
        pm.max_spare_servers = 20
        pm.max_requests = 500
      '';
    };
  };

}
