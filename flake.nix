{
  description = "Cisco SNMP monitoring management environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "aarch64-darwin"; # Apple Silicon Mac
      pkgs = import nixpkgs { inherit system; };
      ansibleCoreVersion = "2.20.5";
      ansibleLintVersion = "25.8.2";
    in {
      devShells.${system}.default =
        assert pkgs.ansible.version == ansibleCoreVersion;
        assert pkgs.ansible-lint.version == ansibleLintVersion;
        pkgs.mkShell {
          packages = [
            pkgs.ansible
            pkgs.net-snmp
            pkgs.ansible-lint
            pkgs.jq
          ];

          shellHook = ''
            export ANSIBLE_CONFIG="$PWD/ansible/ansible.cfg"
          '';
        };
    };
}
