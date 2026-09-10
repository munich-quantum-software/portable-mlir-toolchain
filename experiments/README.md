# Portable SDK and Core study

The workflows in this repository run SDK builds, Core wheel construction,
Windows compatibility checks, and paired runtime evaluation on the
`munich-quantum-software` organization's runners. Core does not schedule these
jobs. Its pinned checkout supplies the package, training corpus, benchmarks, and
correctness tests.

The [study plan](PLAN.md) defines the comparisons and adoption gates. Trial
artifacts do not change published SDKs or setup-action defaults. The
[results](RESULTS.md) distinguish completed measurements from pending gates.

## Execution

1. Dispatch **Portable SDK optimization study** with `stage=sdk` to build the
   native, ThinLTO, and full-LTO library variants. Native tools come from the
   successful SDK seed run `34411299839` in this repository.
2. Dispatch the same workflow with `stage=wheel` and `libraries-run-id` set to
   the SDK study run. Select SDK/Core LTO pairs and the PGO scope explicitly.
3. Dispatch **Paired optimization evaluation** with the wheel study run IDs.
   Each platform runs two independent cohorts of twelve rotating rounds.
4. Run `decide_optimization.py` on the two downloaded cohort files, naming
   native and matched variants. It requires a confidence-supported 10% gain over
   the best native-SDK recipe and rejects confirmed 3% workload regressions.
5. Run **Native SDK Windows compatibility** for x64 and ARM64. Windows retains
   its current compiler and optimization settings.

All run IDs consumed by these workflows belong to this repository. Keep source,
compiler, SDK, target, profile, and artifact identities with every result.
Cancel superseded jobs instead of leaving duplicate experiments running.

`warm-cache=true` additionally measures clean rebuilds with the seeded compiler
cache and the same profile. Those timings exclude fresh training, BOLT, repair,
compression, and upload, and must be reported separately from cold pipelines.

## Local checks

The scripts accept `--core` for an existing Core checkout. For example:

```console
uv run --no-project --python 3.14 --with pytest pytest experiments/tests
python3 -m unittest discover -s tests
python3 experiments/evaluate_optimization.py /path/to/artifacts \
  native-variant matched-variant --core /path/to/core --cpu 19
```

Run latency measurements without concurrent builds. Linux measurements pin one
available CPU; macOS records the host and measures all candidates on that host.
The migrated experiment files retain their [MIT license](LICENSE).
