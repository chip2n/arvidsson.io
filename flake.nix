{
  description = "My personal website";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
  };
  outputs = { self, nixpkgs, ... }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    trivial-file-watch = pkgs.sbcl.buildASDFSystem {
      pname = "trivial-file-watch";
      version = "0.0.1";
      src = pkgs.fetchFromGitHub {
        owner = "chip2n";
        repo = "trivial-file-watch";
        rev = "cdb1bd21bee4944e19a934b97b1c836161878752";
        hash = "sha256-Jgo52cso68Bn5RfWyjUQVsGiICT/80dKoO2n5yJD014=";
      };
      systems = [ "trivial-file-watch" ];
      lispLibs = with pkgs.sbcl.pkgs; [
        bt-semaphore
        cl-inotify
        cl-fad
      ];
    };
    site = pkgs.sbcl.buildASDFSystem {
      pname = "site";
      version = "1.0.0";
      src = ./.;
      systems = [ "site" ];
      lispLibs = with pkgs.sbcl.pkgs; [
        alexandria
      ];
    };
    siteDev = pkgs.sbcl.buildASDFSystem {
      pname = "siteDev";
      version = "1.0.0";
      src = ./.;
      systems = [ "site" "site/live" ];
      lispLibs = with pkgs.sbcl.pkgs; [
        alexandria
        trivial-file-watch
        clack
        clack-handler-hunchentoot
        lack-middleware-static
        websocket-driver
      ];
    };
    sbclDeploy = pkgs.sbcl.withOverrides (self: super: {
      inherit site;
    });
    sbclDev = pkgs.sbcl.withOverrides (self: super: {
      inherit siteDev;
    });
    lispDeploy = sbclDeploy.withPackages (ps: [ ps.site ]);
    lispDev = sbclDev.withPackages (ps: [ ps.siteDev ]);
    build-site = pkgs.writeScriptBin "build-site" ''
      #!/usr/bin/env bash
      ./fetch-deps.sh
      ${lispDeploy}/bin/sbcl \
          --no-userinit \
          --non-interactive \
          --eval '(require :asdf)' \
          --eval '(require :site)' \
          --eval '(site:compile-pages)'
    '';
  in {
    apps.${system} = {
      default = {
        type = "app";
        program = "${build-site}/bin/build-site";
      };
    };
    packages.${system}.default = build-site;
    devShells.${system}.default = with pkgs; mkShell {
      LD_LIBRARY_PATH = "${lib.makeLibraryPath [ openssl ]}";
      packages = [ lispDev ];
    };
  };
}
