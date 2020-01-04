{ nixpkgsRev
, ghcVersion
, projectRoot
, sourceOverrides ? _: {}
, tools ? (_: [])
}:

let

  githubTarball = owner: repo: rev:
    builtins.fetchTarball { url = "https://github.com/${owner}/${repo}/archive/${rev}.tar.gz"; };

  nixPkgs = import (githubTarball "NixOS" "nixpkgs" nixpkgsRev) { inherit config; };

  config = {
    packageOverrides = pkgs: rec {
      haskellPackages = pkgs.haskell.packages."${ghcVersion}".override {
        overrides = self: super: (sourceOverrides depsTools) // builtins.mapAttrs (name: path: super.callCabal2nix name (gitignore path) {}) projectPackages;
      };
    };
  };

  gitignore = nixPkgs.nix-gitignore.gitignoreSourcePure [ "${projectRoot}/.gitignore" ];

  # https://gist.github.com/codebje/000df013a2a4b7c10d6014d8bf7bccf3
  projectPackages = with builtins; let
    contents = readFile "${projectRoot}/cabal.project";
    trimmed = replaceStrings ["packages:" " "] ["" ""] contents;
    packages = filter (x: builtins.isString x && x != "") (split "\n" trimmed);
    package = p: substring 0 (stringLength p - 1) p;
    paths = map (p: let p' = package p; in { name = p'; value = projectRoot + "/${p'}"; } ) packages;
    in listToAttrs paths;

  dontCheckDeps =
    with nixPkgs.haskell.lib;
    builtins.mapAttrs (name: dep: dontCheck dep);
  
  githubDep = owner: repo: rev:
    nixPkgs.haskellPackages.callCabal2nix repo (githubTarball owner repo rev) {};

  hackageDep = pkg: ver:
    nixPkgs.haskellPackages.callCabal2nix pkg (builtins.fetchTarball {
      url = "http://hackage.haskell.org/package/${pkg}-${ver}/${pkg}-${ver}.tar.gz";
    }) {};

  depsTools = {
    inherit dontCheckDeps githubDep hackageDep;
  };

in {
  pkgs = nixPkgs;
  
  shell = with nixPkgs; with haskellPackages; shellFor {
    packages = p: map (name: builtins.getAttr name p) (builtins.attrNames projectPackages);
    buildInputs = with haskellPackages; [
      ghc
      cabal-install
    ] ++ (tools pkgs);
  };
}
