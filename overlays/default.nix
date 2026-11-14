{ inputs }:
final: prev:
{
  # Avoid TLS certificate test failures in the main nixpkgs mitmproxy build.
  mitmproxy = inputs.nixpkgs-pinned.legacyPackages.${prev.stdenv.hostPlatform.system}.mitmproxy;
  ghostty = prev.ghostty.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ../pkgs/ghostty-split-tab-navigation.patch
    ];
  });
  yokai-clipboard = final.callPackage ../pkgs/yokai-clipboard.nix { };
  yokai-shell = final.callPackage ../pkgs/yokai-shell.nix { };
  yokai-updates = final.callPackage ../pkgs/yokai-updates.nix { };
  superfile = final.callPackage ../pkgs/superfile.nix { superfile = prev.superfile; };
}
