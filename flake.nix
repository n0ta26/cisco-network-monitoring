{
  description = "Cisco SNMP monitoring management environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "aarch64-darwin"; # Apple Silicon Mac
      pkgs = import nixpkgs { inherit system; };
    in {
      devShells.${system}.default = pkgs.mkShell {
        packages = [
          pkgs.ansible
          pkgs.net-snmp
          pkgs.ansible-lint
        ];

        shellHook = ''
          export ANSIBLE_CONFIG="$PWD/ansible/ansible.cfg"
        '';
      };
    };
}
