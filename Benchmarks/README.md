# Candoa Battery Benchmark

Reproducible methodology for comparing Candoa's energy use against Arc, Brave,
and Zen on the same Mac. Publish the protocol with the numbers — reproducibility
is what makes the claim credible to developers.

## Why Candoa should win

- **System WebKit.** Candoa rides the same engine processes as Safari — Apple's
  hardware media decode paths, OS-managed process suspension, and an Apple
  Silicon–tuned JIT. Chromium (Arc, Brave) and Gecko (Zen) ship their own.
- **Tab hibernation.** Background tabs idle for 15+ minutes give up their
  WebContent process entirely; state is restored instantly on activation.
- **True background throttling.** Idle background tabs leave the view
  hierarchy so WebKit throttles their timers and rendering toward zero.
- **Network-process content blocking.** Tracker/ad requests are blocked by a
  compiled `WKContentRuleList` — they never load, never execute.

## Protocol

1. Same Mac, same macOS, fully charged and **plugged in**, display at fixed
   brightness, auto-brightness off. Quit everything except the browser under
   test (including Safari, so WebKit helper processes attribute cleanly).
2. Fresh boot or at least 5 minutes of idle before each run.
3. Record the idle baseline first:
   `sudo ./battery-bench.sh baseline 'match-nothing^' 600`
4. Launch ONE browser, open the identical tab set:
   `./open-tabs.sh "Brave Browser"` (or open `urls.txt` manually).
   Let the YouTube tab play muted at 480p in the background — identical
   state in every browser.
5. Wait 2 minutes for load to settle, then sample 10 minutes:
   `sudo ./battery-bench.sh brave 'Brave' 600`
6. Quit the browser fully, repeat for the next one:
   - `sudo ./battery-bench.sh candoa  'Candoa|com.apple.WebKit' 600`
   - `sudo ./battery-bench.sh arc   'Arc' 600`
   - `sudo ./battery-bench.sh zen   'zen|plugin-container' 600`
7. For the hibernation story, run a second Candoa pass after the tabs have been
   idle 20+ minutes (`candoa-hibernated`) — that's the headline delta.
8. Run the full matrix 3 times and use medians. Results land in
   `results/summary.csv`.

Subtract the baseline run's package power from each browser's to get the
browser-attributable power. Report both raw and baseline-corrected numbers.

## Memory benchmark

`memory-bench.sh` samples the browser's total resident memory (no sudo
needed) and is designed to capture the hibernation cliff:

1. Open the identical tab set, then hands off the machine — interacting with
   tabs resets their idle timers.
2. Run for 40 minutes: `./memory-bench.sh candoa 'Candoa|com.apple.WebKit' 2400`
   (same process patterns as the battery script).
3. The `final_mb` column is the headline: after the 15-minute idle threshold,
   Candoa's background tabs give up their WebContent processes while Chromium
   (Arc, Brave) and Gecko (Zen) stay flat or grow. Plot the per-label
   `results/<label>-memory.csv` time series for the chart — the cliff is the
   story.

Caveat to state when publishing: RSS over-counts memory shared between
processes, but it over-counts every browser the same way, so the comparison
is fair even though absolute numbers read high.

## Results

| Browser | Avg CPU (all processes) | Pkg power vs baseline | Energy (10 min) | Memory at T+40min |
|---|---|---|---|---|
| Candoa | | | | |
| Candoa (tabs hibernated) | | | | |
| Arc | | | | |
| Brave | | | | |
| Zen | | | | |

## Post template

> Candoa (my WebKit browser) vs Arc vs Brave vs Zen — identical 12 tabs,
> 10 min, M-series MacBook, measured with powermetrics:
>
> Candoa: __ mWh
> Zen: __ mWh
> Brave: __ mWh
> Arc: __ mWh
>
> Same tabs. __× less energy than Arc. Methodology + scripts in the repo. 🧵

Honesty rules for the post: state the hardware, attach the methodology,
publish the raw `results/` output, and never compare against a browser running
extensions you didn't install on the others.
