{
  description = "Agent skills for Holochain hApp development (Holochain 0.7)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f {
        inherit system;
        pkgs = nixpkgs.legacyPackages.${system};
      });

      # Every directory under skills/ that holds a SKILL.md. Adding a second
      # skill is a new directory, not an edit to this file.
      skillNames = builtins.attrNames (nixpkgs.lib.filterAttrs
        (name: type: type == "directory" && builtins.pathExists ./skills/${name}/SKILL.md)
        (builtins.readDir ./skills));

      version =
        let pkg = builtins.fromJSON (builtins.readFile ./package.json);
        in pkg.version;
    in
    {
      lib.mkSkillsHook = import ./nix/mk-skills-hook.nix { inherit (nixpkgs) lib; };

      packages = forAllSystems ({ pkgs, ... }:
        let
          # One derivation per skill. Its root IS the skill, so it can be
          # rsynced or symlinked straight into .claude/skills/<name>/.
          individual = nixpkgs.lib.genAttrs skillNames (name:
            pkgs.callPackage ./nix/skill.nix {
              inherit name version;
              src = ./.;
            });

          # The bundle: one directory per skill, matching the shape of the
          # release tarball, so `${bundle}/holochain/SKILL.md` and
          # `tar -xzf ... -C .claude/skills` land the same tree.
          bundle = pkgs.runCommand "holochain-agent-skills-${version}" { } ''
            mkdir -p "$out"
            ${nixpkgs.lib.concatMapStrings (name: ''
              cp -r ${individual.${name}} "$out/${name}"
            '') skillNames}
          '';
        in
        individual // { default = bundle; bundle = bundle; });

      checks = forAllSystems ({ pkgs, system, ... }: {
        # `nix flake check` runs the same two gates CI runs, so a Nix consumer
        # cannot pull a tree that would fail the repository's own validator.
        validate = pkgs.runCommand "validate-skill" { buildInputs = [ pkgs.coreutils pkgs.gnused pkgs.gnugrep pkgs.gawk pkgs.findutils ]; } ''
          cd ${./.}
          sh scripts/validate-skill.sh
          sh scripts/eval/run-eval.sh
          touch "$out"
        '';
      } // self.packages.${system});

      devShells = forAllSystems ({ pkgs, ... }: {
        default = pkgs.mkShell {
          packages = [ pkgs.bun pkgs.mdbook pkgs.nodejs_24 ];
          shellHook = ''
            echo "holochain-agent-skills dev shell"
            echo "  bun run validate   structural and currency gate"
            echo "  bun run eval       routing regression floor"
            echo "  bun run build      compile the installer to bin/install.mjs"
            echo "  mdbook serve       preview the documentation site"
          '';
        };
      });

      formatter = forAllSystems ({ pkgs, ... }: pkgs.nixpkgs-fmt);
    };
}
