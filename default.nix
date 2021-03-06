{ system ? builtins.currentSystem # TODO: Get rid of this system cruft
, iosSdkVersion ? "10.2"
}:
let

  origObelisk = import ./.obelisk/impl {
    inherit system iosSdkVersion;
  };
  opkgs = origObelisk.reflex-platform.nixpkgs;
  ignorePaths =
    [ ".git" "tags" "TAGS" "README.md" "dist" "dist-newstyle"
      "frontend.jsexe.assets" "static.assets" "result-exe"
      "zeus-access-token" "zeus-cache-key.pub"
      "zeus-cache-key.sec" "zeus.db" "migrations.md"
    ];


  myMkObeliskApp =
    { exe
    , routeHost
    , enableHttps
    , name ? "backend"
    , user ? name
    , group ? user
    , baseUrl ? "/"
    , internalPort ? 8000
    , backendArgs ? "--port=${toString internalPort}"
    , ...
    }: {...}: {
      services.nginx = {
        enable = true;
        virtualHosts."${routeHost}" = {
          enableACME = enableHttps;
          forceSSL = enableHttps;
          locations.${baseUrl} = {
            proxyPass = "http://localhost:" + toString internalPort;
            proxyWebsockets = true;
          };
        };
      };
      systemd.services.${name} = {
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        restartIfChanged = true;
        path = [
          opkgs.awscli
          opkgs.git
          opkgs.gnutar
          opkgs.gzip
          opkgs.nix
        ];
        script = ''
          ln -sft . '${exe}'/*
          mkdir -p log
          exec ./backend ${backendArgs} >>backend.output 2>&1 </dev/null
        '';
        serviceConfig = {
          User = user;
          KillMode = "process";
          WorkingDirectory = "~";
          Restart = "always";
          RestartSec = 5;
        };
      };
      users = {
        users.${user} = {
          description = "${user} service";
          home = "/var/lib/${user}";
          createHome = true;
          isSystemUser = true;
          group = group;
        };
        groups.${group} = {};
      };
    };

  myServerModules = origObelisk.serverModules // {
    mkObeliskApp = myMkObeliskApp;
  };

  newObelisk = origObelisk // {
    path = builtins.filterSource (path: type: !(builtins.any (x: x == baseNameOf path) ignorePaths ||
                                                builtins.match ".swp$" path)) ./.;
    serverModules = myServerModules;

    server = { exe, hostName, adminEmail, routeHost, enableHttps, version }@args:
      let
        nixos = import (opkgs.path + /nixos);
      in nixos {
        system = "x86_64-linux";
        configuration = {
          imports = [
            (origObelisk.serverModules.mkBaseEc2 args)
            (myMkObeliskApp args)
          ];
        };
      };


  };

in

newObelisk.project ./. ({ pkgs, ... }: {
  overrides = self: super: with pkgs.haskell.lib;
  let beam-src = pkgs.fetchFromGitHub {
        owner = "tathougies";
        repo = "beam";
        rev = "737b73c6ec1c6aac6386bf9592a02a91f34a9478";
        sha256 = "02xc4qgc7kb0rv8g9dq69p3p0d2psp6b4mzq444hsavnsw2wsn9y";
      };
      semantic-reflex-src = pkgs.fetchFromGitHub {
        owner = "tomsmalley";
        repo = "semantic-reflex";
        rev = "728e6263d1d4ce209f02bb5b684971fbef864a95";
        sha256 = "1rh5hf40ay7472czqnjvzlmd4lsspxd2hshiarscadshml3scwfr";
      };
  in {
    backend = overrideCabal super.backend (drv: {
      executableSystemDepends = drv.executableSystemDepends or [] ++ [
        pkgs.awscli
        pkgs.git
        pkgs.gnutar
        pkgs.gzip
        pkgs.nix
      ];
    });
    base32-bytestring = (self.callCabal2nix "base32-bytestring" (pkgs.fetchFromGitHub {
        owner = "FilWisher";
        repo = "base32-bytestring";
        rev = "0c4790ba150a35f7d0d56fe7262ccbe8407c2471";
        sha256 = "1y0qifp8za9s8dzsflw51wyacpjwx4b8p0qpa4xxv46lc2c2gl6i";
    }) {});

    # aeson = dontCheck (self.callCabal2nix "aeson" (pkgs.fetchFromGitHub {
    #     owner = "bos";
    #     repo = "aeson";
    #     rev = "378ff1483876d794fc33adb70e4b69a089a1b841";
    #     sha256 = "06wdwlxa6l5nzkpf7w5sqj10rnxbqd85d9v3j6567n5rc1cyy83c";
    # }) {});
    barbies = dontCheck (self.callCabal2nix "barbies" (pkgs.fetchFromGitHub {
        owner = "jcpetruzza";
        repo = "barbies";
        rev = "3e50449afcc7c094657df86e82f8b77a2ab0aa95";
        sha256 = "1yaln3xisqacw0arxmclncay9a4xj2i6fpacjnpdaigxakl9xdwv";
    }) {});
    beam-core = dontCheck (self.callCabal2nix "beam-core" "${beam-src}/beam-core" {});
    beam-migrate = doJailbreak (dontCheck (self.callCabal2nix "beam-migrate" "${beam-src}/beam-migrate" {}));
    beam-sqlite = dontCheck (self.callCabal2nix "beam-sqlite" "${beam-src}/beam-sqlite" {});

    github = dontHaddock (doJailbreak (dontCheck (self.callCabal2nix "github" (pkgs.fetchFromGitHub {
        owner = "mightybyte";
        repo = "github";
        rev = "a149ee362f74935836f1fa55572842905636ea7c";
        sha256 = "0fx4fmacw0b8gkld4zmc4n611vv41l91l1wchi3zprf9sdi658fy";
    }) {})));
    heist = dontCheck (self.callCabal2nix "heist" (pkgs.fetchFromGitHub {
        owner = "snapframework";
        repo = "heist";
        rev = "de802b0ed5055bd45cfed733524b4086c7e71660";
        sha256 = "0gqvw9jp6pxg4pixrmlg7vlcicmhkw2cb39bb8lfw401yaq6ad4a";
    }) {});
    lens-aeson = dontCheck super.lens-aeson;
    reflex-dom-contrib = dontCheck (self.callCabal2nix "reflex-dom-contrib" (pkgs.fetchFromGitHub {
        owner = "reflex-frp";
        repo = "reflex-dom-contrib";
        rev = "796a3f0fa1ff59cbad97c918983355b46c3b6aa0";
        sha256 = "0aqj7xm97mwxhhpcrx58bbg3hhn12jrzk13lf4zhpk2rrjw6yvmc";
    }) {});
    scrub = dontCheck (self.callCabal2nix "scrub" (pkgs.fetchFromGitHub {
        owner = "mightybyte";
        repo = "scrub";
        rev = "38a1e241e04e1e8ace266a2df51650492aaa1279";
        sha256 = "1as5kfryjxs2mv47wq6pkxq2m7jf6bihx4qrj1mvk31qyg5qghr2";
    }) {});
    semantic-reflex = dontHaddock (dontCheck
      (self.callCabal2nix "semantic-reflex" "${semantic-reflex-src}/semantic-reflex" {}));
    shelly = dontCheck (self.callCabal2nix "snap-server" (pkgs.fetchFromGitHub {
        owner = "yesodweb";
        repo = "Shelly.hs";
        rev = "cf2f48a298ce7a40da0283702a3d98d53db9027a";
        sha256 = "14m3zp4f2n14chl4d0mb1n8i8kgx3x504h28zpjcvp27ffrxr1cl";
    }) {});
    snap-server = dontCheck (self.callCabal2nix "snap-server" (pkgs.fetchFromGitHub {
        owner = "snapframework";
        repo = "snap-server";
        rev = "dad24ba290126b1b93da32ef6019393329b54ed3";
        sha256 = "0fzbvysq6qkbjd39bphbirzd2xaalm3jaxrs91g04ya17nqdaz1i";
    }) {});
    streaming-lzma = dontCheck (self.callCabal2nix "streaming-lzma" (pkgs.fetchFromGitHub {
        owner = "haskell-hvr";
        repo = "streaming-lzma";
        rev = "ec8cb2f935ee4f3217c6939684103ba1a6bc4ad1";
        sha256 = "1w77v9isv6rmajg4py4ry7475d3xjs7471dfaf6bglbwphm0dj8b";
    }) {});
    zeus = addBuildDepends super.zeus [ pkgs.git ];

  };
  shellToolOverrides = ghc: super: {
    inherit (pkgs) git;
    inherit (pkgs) nix;
    inherit (ghc) hlint;
  };
})
