{
  description = "Flake for development workflows.";

  inputs = {
    flake-utils.follows = "rainix/flake-utils";
    rainix.url = "github:rainlanguage/rainix";
  };

  outputs =
    { flake-utils, rainix, ... }:
    flake-utils.lib.eachDefaultSystem (system: {
      packages = rainix.packages.${system};
      devShells.default = rainix.devShells.${system}.sol-shell;
    });
}
