#!/usr/bin/env python3
"""

Calculate decay heat power following reactor shutdown using empirical correlations.

Models available:
  • Simple power-law:    P_decay(t) = C · P0 · t^(–n)
  • Multi-term power-law: P_decay(t) = P0 · Σ [a_i · t^(–n_i)]

Example usage:
    python decay_heat_calculator.py \
        --power 3000      \  # P₀ = 3000 MW_th
        --model simple    \
        --C 0.066 --n 0.2 \
        --tmin 1 --tmax 86400 --points 100 \
        --units s

    python decay_heat_calculator.py \
        --power 3000 --model multiterm \
        --coeff "0.040,0.2" "0.020,0.1" "0.005,0.05" \
        --tmin 1 --tmax 86400 --points 100 --units s
"""

import numpy as np
import matplotlib.pyplot as plt
import argparse

def simple_decay_heat(P0, t, C, n):
    """
    Simple power-law decay heat:
        H(t) = C · P0 · t^(–n)

    Arguments:
      P0 : float
        Initial reactor power (same units as result, e.g. MW).
      t  : array_like
        Time since shutdown (in seconds).
      C  : float
        Correlation constant (≈0.066).
      n  : float
        Exponent (≈0.2).
    """
    return P0 * C * np.power(t, -n)

def multiterm_decay_heat(P0, t, coeffs):
    """
    Multi-term power-law decay heat:
        H(t) = P0 · Σ [a_i · t^(–n_i)]

    Arguments:
      P0     : float
        Initial reactor power.
      t      : array_like
        Time since shutdown (in seconds).
      coeffs : list of (a_i, n_i) tuples
        Each term's coefficient and exponent.
    """
    H = np.zeros_like(t)
    for a, n in coeffs:
        H += P0 * a * np.power(t, -n)
    return H

def parse_coeff_list(str_list):
    """
    Convert list of "a,n" strings to list of (float(a), float(n)).
    """
    coeffs = []
    for term in str_list:
        a_str, n_str = term.split(',')
        coeffs.append((float(a_str), float(n_str)))
    return coeffs

def main():
    parser = argparse.ArgumentParser(
        description="Decay Heat Calculator"
    )
    parser.add_argument("--power",   type=float, required=True,
                        help="Initial reactor power P₀ (e.g. 3000 for 3000 MW)")
    parser.add_argument("--model",   choices=["simple", "multiterm"],
                        default="simple", help="Choose decay-heat model")
    parser.add_argument("--C",       type=float, default=0.066,
                        help="C constant for simple model")
    parser.add_argument("--n",       type=float, default=0.2,
                        help="Exponent n for simple model")
    parser.add_argument("--coeff",   nargs="+",
                        help="List of a,n pairs for multiterm model, e.g. '0.04,0.2'")
    parser.add_argument("--tmin",    type=float, default=1.0,
                        help="Minimum time since shutdown")
    parser.add_argument("--tmax",    type=float, default=86400.0,
                        help="Maximum time since shutdown")
    parser.add_argument("--points",  type=int, default=100,
                        help="Number of time points to evaluate")
    parser.add_argument("--units",   choices=["s","m","h","d"], default="s",
                        help="Units for tmin/tmax: seconds, minutes, hours, days")

    args = parser.parse_args()

    # Time-unit conversion to seconds
    unit_factors = {"s": 1.0, "m": 60.0, "h": 3600.0, "d": 86400.0}
    factor = unit_factors[args.units]
    tmin_s = args.tmin * factor
    tmax_s = args.tmax * factor

    # Generate time array (log-spaced for better coverage)
    t = np.logspace(np.log10(tmin_s), np.log10(tmax_s), args.points)

    # Compute decay heat
    if args.model == "simple":
        H = simple_decay_heat(args.power, t, args.C, args.n)
    else:
        coeffs = parse_coeff_list(args.coeff)
        H = multiterm_decay_heat(args.power, t, coeffs)

    # Print results in a simple table
    print(f"{'Time ('+args.units+')':>12} | {'Decay Heat':>12}")
    print("-" * 27)
    for ti, Hi in zip(t / factor, H):
        print(f"{ti:12.3f} | {Hi:12.3f}")

    # Plot decay heat vs time on log-log scale
    plt.figure(figsize=(8,5))
    plt.loglog(t, H, marker='o', linestyle='-')
    plt.title("Decay Heat vs Time Since Shutdown")
    plt.xlabel(f"Time since shutdown ({args.units})")
    plt.ylabel("Decay heat power (same units as P₀)")
    plt.grid(True, which="both", ls="--", alpha=0.5)
    plt.tight_layout()
    plt.show()

if __name__ == "__main__":
    main()

