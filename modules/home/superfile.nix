{ ... }:
{
  programs.superfile = {
    settings = {
      theme = "yokai";
      transparent_background = false;
      cd_on_quit = true;
      # Superfile fills omitted options from its built-in defaults.
      ignore_missing_fields = true;
    };
    themes.yokai = ../../config/superfile/yokai.toml;
  };
  xdg.configFile."superfile/shell.zsh".source = ../../config/superfile/shell.zsh;
}
