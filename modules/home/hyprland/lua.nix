# Helpers for Home Manager's Lua generator; quote shell commands with toLua.
{ lib }:
rec {
  inline = lib.generators.mkLuaInline;
  toLua = lib.generators.toLua { };
  dsp = expr: inline "hl.dsp.${expr}";
  exec = cmd: inline "hl.dsp.exec_cmd(${toLua cmd})";
  bind = keys: dispatcher: { _args = [ keys dispatcher ]; };
  bindWith = flags: keys: dispatcher: { _args = [ keys dispatcher flags ]; };
}
