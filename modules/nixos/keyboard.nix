{ ... }:
{
  services.keyd = {
    enable = true;
    keyboards.default = {
      ids = [ "*" ];
      # Preserve the Compose key as an additional Meta modifier.
      settings.main.compose = "layer(meta)";
    };
  };
}
