{ ... }:
{
  xdg.configFile."ghostty/config".text = builtins.readFile ../../config/ghostty/config + ''
    gtk-custom-css = ${../../config/ghostty/tabs.css}
  '';
  xdg.configFile."xdg-terminals.list".text = "com.mitchellh.ghostty.desktop\n";

  # Copy the file out of the store before running the interactive p10k wizard.
  home.file.".p10k.zsh".source = ../../config/p10k/.p10k.zsh;

}
