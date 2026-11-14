{ ... }:
{
  programs.mpv = {
    config = {
      vo = "gpu-next";
      tone-mapping = "bt.2390";
      hdr-compute-peak = "yes";
      hwdec = "auto-safe";
      profile = "high-quality";
      save-position-on-quit = "yes";
    };
  };

}
