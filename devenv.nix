{ pkgs, lib, config, inputs, ... }:

{
  # https://devenv.sh/basics/
  env = {
    GREET = "nimri-ipc";
  };

  # https://devenv.sh/packages/
  packages = [
    pkgs.git
    pkgs.nim
    pkgs.nimble
  ];

  # https://devenv.sh/languages/
  languages = {};

  # https://devenv.sh/scripts/
  scripts.hello.exec = ''
    echo "nimri-ipc dev environment"
  '';

  enterShell = ''
    hello
    git --version
    nim --version | head -n 1
    nimble --version
  '';

  # https://devenv.sh/tests/
  enterTest = ''
    echo "Running tests"
    git --version | grep --color=auto "${pkgs.git.version}"
    nim --version >/dev/null
    nimble --version >/dev/null
  '';

  # See full reference at https://devenv.sh/reference/options/
}
