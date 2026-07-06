//! Safeguarded Newton (`rtsafe`) root-finder for `Σ amount / (1 + rate)^t = 0`,
//! a Rust port of the pure-Elixir `Finance.Solver.Newton`. Kept deliberately in
//! lockstep with that implementation so results match to `:precision`.

use rayon::prelude::*;
use rustler::Atom;

mod atoms {
    rustler::atoms! {
        ok,
        did_not_converge,
    }
}

// Net present value: Σ amount / (1 + rate)^t. Discounts with a negative exponent
// so the factor underflows to 0 at high rates instead of overflowing — matching
// the pure-Elixir `present_value/2`, which does the same to dodge `:math.pow`
// raising on overflow.
fn npv(times: &[f64], amounts: &[f64], rate: f64) -> f64 {
    times
        .iter()
        .zip(amounts)
        .map(|(&t, &a)| a * (1.0 + rate).powf(-t))
        .sum()
}

// Derivative wrt rate: Σ -t * amount / (1 + rate)^(t + 1)
fn dnpv(times: &[f64], amounts: &[f64], rate: f64) -> f64 {
    times
        .iter()
        .zip(amounts)
        .map(|(&t, &a)| -t * a * (1.0 + rate).powf(-(t + 1.0)))
        .sum()
}

// Bracket floor that keeps the longest-dated flow's discount factor finite.
fn safe_low(times: &[f64]) -> f64 {
    let max_t = times.iter().copied().fold(1.0_f64, f64::max);
    (1.0e-290_f64).powf(1.0 / max_t).max(1.0e-6) - 1.0
}

fn straddles_zero(a: f64, b: f64) -> bool {
    (a <= 0.0 && b >= 0.0) || (a >= 0.0 && b <= 0.0)
}

// Geometric grid for the bracket scan: grow `1 + rate` by 5% per step, up to 1e7.
const SCAN_RATIO: f64 = 1.05;
const SCAN_CAP: f64 = 1.0e7;

fn grid_step(rate: f64) -> f64 {
    (1.0 + rate) * SCAN_RATIO - 1.0
}

// Distance from the interval [low, high] to `guess`; an interval that contains the
// guess wins outright.
fn distance(low: f64, high: f64, guess: f64) -> f64 {
    if low <= guess && guess <= high {
        0.0
    } else {
        (low - guess).abs().min((high - guess).abs())
    }
}

// Walk a geometric grid of rates outward from the floor; among every adjacent-sample
// sign change, keep the interval whose nearer edge sits closest to `guess`. Returns
// the bracketing interval, or None when the NPV never crosses zero. Mirrors
// `Finance.Shared.bracket/2`: sampling the interior (not just the extremes) finds a
// root even when the curve crosses zero an even number of times, and anchoring to
// `guess` selects the same root a guess-driven spreadsheet would.
fn bracket(times: &[f64], amounts: &[f64], guess: f64) -> Option<(f64, f64)> {
    let low = safe_low(times);
    let mut prev = low;
    let mut f_prev = npv(times, amounts, low);
    let mut rate = grid_step(low);
    let mut best: Option<(f64, f64)> = None;

    while rate <= SCAN_CAP {
        let f = npv(times, amounts, rate);

        if straddles_zero(f_prev, f) {
            best = match best {
                Some(b) if distance(b.0, b.1, guess) <= distance(prev, rate, guess) => Some(b),
                _ => Some((prev, rate)),
            };

            // Stop at the first sign change reaching the guess: it either contains
            // the guess or is the nearest interval above it, and `best` already holds
            // the nearest below.
            if rate >= guess {
                return best;
            }
        }

        prev = rate;
        f_prev = f;
        rate = grid_step(rate);
    }

    best
}

fn inside(point: f64, xlo: f64, xhi: f64) -> bool {
    point >= xlo.min(xhi) && point <= xlo.max(xhi)
}

// The converged rate, or None when no root can be bracketed or the computation
// went non-finite (extreme magnitudes — mirrors the Elixir overflow guard).
fn rtsafe(times: &[f64], amounts: &[f64], guess: f64, tol: f64, max_iter: i64) -> Option<f64> {
    let (low, high) = bracket(times, amounts, guess)?;

    // Orient so the NPV is negative at `xlo`, positive at `xhi`.
    let (mut xlo, mut xhi) = if npv(times, amounts, low) < 0.0 {
        (low, high)
    } else {
        (high, low)
    };

    let mut x = if guess > low && guess < high {
        guess
    } else {
        (low + high) / 2.0
    };
    let mut dxold = (high - low).abs();
    let mut f = npv(times, amounts, x);
    let mut df = dnpv(times, amounts, x);

    for _ in 0..max_iter {
        if !f.is_finite() || !df.is_finite() {
            return None;
        }

        // Prefer Newton when the derivative isn't flat, the step lands inside the
        // bracket, and it shrinks the interval by at least half. Comparing the
        // Newton point to the bracket (not the `((x-xhi)*df - f)*((x-xlo)*df - f)`
        // product) avoids overflow in the steep zone near the bracket floor.
        let newton = x - f / df;
        let use_newton =
            df != 0.0 && inside(newton, xlo, xhi) && (2.0 * f).abs() <= (dxold * df).abs();

        let (next, dx) = if use_newton {
            (newton, f / df)
        } else {
            let step = (xhi - xlo) / 2.0;
            (xlo + step, step)
        };

        if dx.abs() < tol {
            return next.is_finite().then_some(next);
        }

        x = next;
        f = npv(times, amounts, x);
        df = dnpv(times, amounts, x);
        if f < 0.0 {
            xlo = x;
        } else {
            xhi = x;
        }
        dxold = dx;
    }

    x.is_finite().then_some(x)
}

fn result(times: &[f64], amounts: &[f64], guess: f64, tol: f64, max_iter: i64) -> (Atom, f64) {
    match rtsafe(times, amounts, guess, tol, max_iter) {
        Some(rate) => (atoms::ok(), rate),
        None => (atoms::did_not_converge(), 0.0),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn nif_solve(
    times: Vec<f64>,
    amounts: Vec<f64>,
    guess: f64,
    tol: f64,
    max_iter: i64,
) -> (Atom, f64) {
    result(&times, &amounts, guess, tol, max_iter)
}

// Solve a whole batch in one call, in parallel across a rayon thread pool.
#[rustler::nif(schedule = "DirtyCpu")]
fn nif_solve_many(
    batch: Vec<(Vec<f64>, Vec<f64>)>,
    guess: f64,
    tol: f64,
    max_iter: i64,
) -> Vec<(Atom, f64)> {
    batch
        .par_iter()
        .map(|(times, amounts)| result(times, amounts, guess, tol, max_iter))
        .collect()
}

rustler::init!("Elixir.FinanceRustler.Solver");
