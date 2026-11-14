{ writeShellScriptBin, flatpak, lib, commandLineArgs ? "", extensionPath, extraFlatpakArgs ? [ ] }:

# Home Manager supplies browser flags through commandLineArgs.
writeShellScriptBin "brave" ''
  exec ${flatpak}/bin/flatpak run \
    --talk-name=org.freedesktop.Flatpak \
    --filesystem=/nix/store:ro \
    ${lib.escapeShellArg "--filesystem=${extensionPath}:ro"} \
    ${lib.escapeShellArgs extraFlatpakArgs} \
    com.brave.Browser ${commandLineArgs} "$@"
''
