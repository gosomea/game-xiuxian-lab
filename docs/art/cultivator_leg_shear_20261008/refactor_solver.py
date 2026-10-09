#!/usr/bin/env python3
"""One-shot refactor: replace the sequential polish with a 2x2 Newton solver."""
import ast
import pathlib

P = pathlib.Path("tools/art/cultivator_leg_fix.py")
s = P.read_text()
start = s.index("    # Second move: SEQUENTIAL solve")
end_marker = "    best_pair = (swing_total, foot_total)\n"
end = s.index(end_marker) + len(end_marker)

new_block = '''    # Second move: 2x2 Newton with a finite-difference Jacobian. The two knobs are
    # COUPLED - rotating the foot folds the leg forward and shifts the offset as well
    # (measured: foot +20 deg changed pitch -25 deg AND offset +0.01 m) - so solving them
    # one at a time converged neither. Newton on both at once handles the coupling
    # explicitly: each pass measures all four partials from two probe bakes, then steps
    # both knobs against the local Jacobian.
    swing_total = swing_deg
    foot_total = 0.0
    history = []
    offset, pitch = measure(armature, scene, action, chain, forward)
    best_cost = abs(offset) + abs(pitch)
    best_pair = (swing_total, foot_total)
    probe_swing, probe_foot = 2.0, 4.0
    for pass_index in range(POLISH_PASSES):
        leg_res = -offset
        sole_res = -pitch
        if (abs(leg_res) <= LEG_TOLERANCE_M and abs(sole_res) <= SOLE_TOLERANCE_DEG):
            break
        o_s, p_s = bake_and_measure(swing_total + probe_swing, foot_total)
        o_f, p_f = bake_and_measure(swing_total, foot_total + probe_foot)
        j11 = (o_s - offset) / probe_swing     # d(offset)/d(swing)
        j21 = (p_s - pitch) / probe_swing      # d(pitch)/d(swing)
        j12 = (o_f - offset) / probe_foot      # d(offset)/d(foot)
        j22 = (p_f - pitch) / probe_foot       # d(pitch)/d(foot)
        det = j11 * j22 - j12 * j21
        if abs(det) < 1e-9:
            history.append({"pass": pass_index + 1, "note": "singular jacobian"})
            break
        ds = (leg_res * j22 - sole_res * j12) / det
        df = (sole_res * j11 - leg_res * j21) / det
        # Bound the per-pass step: a wild Jacobian entry must not fling the pose.
        ds = max(min(ds, 6.0), -6.0)
        df = max(min(df, 12.0), -12.0)
        trial_swing = swing_total + ds
        trial_foot = foot_total + df
        trial_offset, trial_pitch = bake_and_measure(trial_swing, trial_foot)
        cost = abs(trial_offset) + abs(trial_pitch)
        improved = cost < best_cost
        history.append({"pass": pass_index + 1,
                        "swing_deg": round(trial_swing, 3),
                        "foot_deg": round(trial_foot, 3),
                        "offset_m": round(trial_offset, 4),
                        "pitch_deg": round(trial_pitch, 3),
                        "accepted": improved})
        if improved:
            swing_total, foot_total = trial_swing, trial_foot
            offset, pitch = trial_offset, trial_pitch
            best_cost, best_pair = cost, (swing_total, foot_total)
        else:
            trial_swing = swing_total + ds * 0.5
            trial_foot = foot_total + df * 0.5
            trial_offset, trial_pitch = bake_and_measure(trial_swing, trial_foot)
            cost = abs(trial_offset) + abs(trial_pitch)
            halved_ok = cost < best_cost
            history.append({"pass": pass_index + 1, "halved": True,
                            "swing_deg": round(trial_swing, 3),
                            "foot_deg": round(trial_foot, 3),
                            "offset_m": round(trial_offset, 4),
                            "pitch_deg": round(trial_pitch, 3),
                            "accepted": halved_ok})
            if halved_ok:
                swing_total, foot_total = trial_swing, trial_foot
                offset, pitch = trial_offset, trial_pitch
                best_cost, best_pair = cost, (swing_total, foot_total)
            else:
                bake_and_measure(*best_pair)
                offset, pitch = measure(armature, scene, action, chain, forward)
                break
'''

new_block = new_block.replace("    best_pair = (swing_total, foot_total)\n", "", 0)
# keep a single best_pair assignment at the top (already inside new_block)
s = s[:start] + new_block + s[end:]
P.write_text(s)
ast.parse(P.read_text())
print("replaced OK, syntax OK")
