//! Safeguarded Newton (`rtsafe`) root-finder for `Σ amount / (1 + rate)^t = 0`,
//! a Rust port of the pure-Elixir `Finance.Solver.Newton`. Kept deliberately in
//! lockstep with that implementation so results match to `:precision`.

use rustler::Atom;

mod atoms {
    rustler::atoms! {
        ok,
        did_not_converge,
    }
}

// Net present value: Σ amount / (1 + rate)^t
fn npv(times: &[f64], amounts: &[f64], rate: f64) -> f64 {
    times
        .iter()
        .zip(amounts)
        .map(|(&t, &a)| a / (1.0 + rate).powf(t))
        .sum()
}

// Derivative wrt rate: Σ -t * amount / (1 + rate)^(t + 1)
fn dnpv(times: &[f64], amounts: &[f64], rate: f64) -> f64 {
    times
        .iter()
        .zip(amounts)
        .map(|(&t, &a)| -t * a / (1.0 + rate).powf(t + 1.0))
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

// Expand the upper bound until the NPV changes sign against `f_low`.
fn bracket(times: &[f64], amounts: &[f64], f_low: f64) -> Option<f64> {
    let mut high = 1.0;
    while high <= 1.0e7 {
        if straddles_zero(f_low, npv(times, amounts, high)) {
            return Some(high);
        }
        high = high * 2.0 + 1.0;
    }
    None
}

fn inside(point: f64, xlo: f64, xhi: f64) -> bool {
    point >= xlo.min(xhi) && point <= xlo.max(xhi)
}

// The converged rate, or None when no root can be bracketed or the computation
// went non-finite (extreme magnitudes — mirrors the Elixir overflow guard).
fn rtsafe(times: &[f64], amounts: &[f64], guess: f64, tol: f64, max_iter: i64) -> Option<f64> {
    let low = safe_low(times);
    let f_low = npv(times, amounts, low);
    let high = bracket(times, amounts, f_low)?;

    // Orient so the NPV is negative at `xlo`, positive at `xhi`.
    let (mut xlo, mut xhi) = if f_low < 0.0 {
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

#[rustler::nif(schedule = "DirtyCpu")]
fn nif_solve(
    times: Vec<f64>,
    amounts: Vec<f64>,
    guess: f64,
    tol: f64,
    max_iter: i64,
) -> (Atom, f64) {
    match rtsafe(&times, &amounts, guess, tol, max_iter) {
        Some(rate) => (atoms::ok(), rate),
        None => (atoms::did_not_converge(), 0.0),
    }
}

rustler::init!("Elixir.FinanceRustler.Solver");
