{
  pkgs ? import <nixpkgs> {}
, ...
}:

pkgs.writeShellScriptBin "neuron-search"
  ''
    set -euo pipefail
    NOTESDIR=''${1}
    FILTERBY=''${2}
    SEARCHFROMFIELD=''${3}
    OPENCMD=`${pkgs.envsubst}/bin/envsubst -no-unset -no-empty <<< ''${4}`
    cd ''${NOTESDIR}
    ${pkgs.ripgrep}/bin/rg --no-heading --no-line-number --with-filename --sort path "''${FILTERBY}" *.md \
      | ${pkgs.fzf}/bin/fzf --tac --no-sort -d ':' -n ''${SEARCHFROMFIELD}.. \
        --preview '${pkgs.bat}/bin/bat --style=plain --color=always {1}' \
      | ${pkgs.gawk}/bin/awk -F: "{printf \"''${NOTESDIR}/%s\", \$1}" \
      | ${pkgs.findutils}/bin/xargs -r ''${OPENCMD}
  ''
