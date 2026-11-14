{ ... }:
{

  programs.gh = {
    settings.git_protocol = "https";
    gitCredentialHelper.enable = true;
  };
}
