# nix/skill.nix — packages one skill from skills/<name>/ as a derivation.
#
# The output root IS the skill: `${skill}/SKILL.md` exists, so the derivation
# can be rsynced or symlinked straight into `.claude/skills/<name>/`. Callers
# that want the tarball shape (a directory holding one subdirectory per skill)
# want `packages.default` instead.
#
# Build-time gate: the skill validator runs in the check phase, so a broken
# routing path or a superseded version pin fails `nix build` rather than
# reaching a consumer's project.
{ lib
, stdenvNoCC
, name
, src
, version
}:

stdenvNoCC.mkDerivation {
  pname = "agent-skill-${name}";
  inherit version src;

  # Nothing to build: the payload is markdown and templates.
  dontConfigure = true;
  dontBuild = true;

  doCheck = true;
  checkPhase = ''
    runHook preCheck

    test -f "$src/skills/${name}/SKILL.md" \
      || { echo "no SKILL.md under skills/${name}/"; exit 1; }

    # The spec requires the frontmatter name to equal the directory name.
    # An installer derives the install path from the directory, so a mismatch
    # produces a skill the agent cannot address.
    declared=$(sed -n 's/^name:[[:space:]]*//p' "$src/skills/${name}/SKILL.md" | head -n 1)
    if [ "$declared" != "${name}" ]; then
      echo "frontmatter name '$declared' does not match directory '${name}'"
      exit 1
    fi

    sh "$src/scripts/validate-skill.sh"

    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -r "$src/skills/${name}/." "$out/"
    runHook postInstall
  '';

  meta = {
    description = "Agent Skills Open Standard skill: ${name}";
    homepage = "https://github.com/Soushi888/holochain-agent-skills";
    license = lib.licenses.asl20;
    platforms = lib.platforms.all;
  };
}
