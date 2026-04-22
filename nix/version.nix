lib:
let
  inherit (builtins)
    readFile
    match
    head
    splitVersion
    concatStringsSep
    ;
  inherit (lib.trivial) pipe;
  inherit (lib.lists) sublist;

  zon = readFile ../build.zig.zon;
  parseVersion =
    name: head (match ".*\n[[:space:]]*\\.${name}[[:space:]]=[[:space:]]\"([^\"]+)\".*" zon);

  version = parseVersion "version";

  zigVersion = pipe "minimum_zig_version" [
    parseVersion
    splitVersion
    (sublist 0 5)
    (concatStringsSep "_")
  ];
in
{
  inherit version zigVersion;
}
