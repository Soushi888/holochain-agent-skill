# nix/mk-skills-hook.nix — builds a devShell `shellHook` fragment that
# materialises agent skills into a project's harness directories.
#
# Every consumer of an agent skill writes the same twelve lines of rsync glue,
# and gets the same two things wrong: forgetting that Nix store paths are
# read-only (so `rsync -a` copies that mode and the NEXT write fails with
# EACCES), and hardcoding one harness path. This function is that glue, once.
#
# Usage from a consumer flake:
#
#   skillsHook = inputs.holochain-agent-skills.lib.mkSkillsHook {
#     inherit pkgs;
#     skills = [
#       { src = inputs.holochain-agent-skills.packages.${system}.holochain; name = "holochain"; }
#       { src = ./local/skills/my-domain;                                   name = "my-domain"; }
#     ];
#   };
#   # then, inside shellHook:
#   ${skillsHook}
#
# `targets` defaults to the three paths the widest set of harnesses scan. Pass
# an explicit list to narrow or extend it; each entry is a path relative to the
# project root.
{ lib }:

{ pkgs
, skills
, targets ? [ ".claude/skills" ".cursor/skills" ".agents/skills" ]
}:

let
  rsync = "${pkgs.rsync}/bin/rsync";

  perSkill = { src, name }:
    lib.concatMapStrings (target: ''
      mkdir -p ${target}
      ${rsync} -a --delete --chmod=u+w ${src}/ ${target}/${name}/
    '') targets;
in
''
  # Agent skills, materialised from the Nix store.
  #
  # --chmod=u+w because store paths are read-only and `rsync -a` preserves that
  # mode on the copy. Without it the next write into the target directory fails
  # with "Permission denied (13)", which surfaces as a broken shellHook on the
  # SECOND `nix develop` rather than the first.
  ${lib.concatMapStrings perSkill skills}
''
