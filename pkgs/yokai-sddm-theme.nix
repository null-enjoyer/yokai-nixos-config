{ runCommand }:
runCommand "yokai-sddm-theme" { } ''
  theme_dir="$out/share/sddm/themes/yokai"
  mkdir -p "$theme_dir/wallpaper"
  cp ${../config/sddm-yokai}/Main.qml "$theme_dir/Main.qml"
  cp ${../config/sddm-yokai}/metadata.desktop "$theme_dir/metadata.desktop"
  cp ${../config/sddm-yokai}/theme.conf "$theme_dir/theme.conf"
  cp ${../config/yokai/Wallpaper.qml} "$theme_dir/wallpaper/Wallpaper.qml"
  ln -s ${../wallpapers} "$theme_dir/wallpapers"
''
