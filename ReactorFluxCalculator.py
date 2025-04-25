#!/usr/bin/env python3
"""

Compute the steady-state neutron flux distribution in a bare, homogeneous
slab reactor using the one-group diffusion equation:

    –D d²φ/dx² + Σₐ φ = S

with zero-flux boundary conditions (φ=0 at x=0 and x=L).

Usage:
    python reactor_flux_calculator.py \
        --length 100 --nodes 501 \
        --D 1.0 --Sigma_a 0.01 --S 1.0
"""

import numpy as np
import matplotlib.pyplot as plt
import argparse

def slab_flux(L: float, D: float, Sigma_a: float, S: float, N: int):
    """
    Solve for φ(x) on [0, L] with φ(0)=φ(L)=0 via finite differences.

    Parameters:
      L       Reactor half-width (cm)
      D       Diffusion coefficient (cm)
      Sigma_a Absorption macroscopic cross-section (1/cm)
      S       Uniform volumetric source term (neutrons/cm³·s)
      N       Number of grid points

    Returns:
      x       Array of positions (cm)
      phi     Array of flux values (neutrons/cm²·s)
    """
    dx = L / (N - 1)
    # Build system matrix A and RHS vector b
    A = np.zeros((N, N))
    b = np.full(N, S)

    # Boundary nodes: φ=0
    A[0,0] = 1.0
    b[0] = 0.0
    A[-1,-1] = 1.0
    b[-1] = 0.0

    # Interior nodes: –D (φ_{i+1} – 2φ_i + φ_{i-1})/dx² + Σₐ φ_i = S
    coeff = D / dx**2
    for i in range(1, N-1):
        A[i, i-1] = -coeff
        A[i, i  ] =  2*coeff + Sigma_a
        A[i, i+1] = -coeff

    # Solve linear system
    phi = np.linalg.solve(A, b)
    x = np.linspace(0, L, N)
    return x, phi

def main():
    parser = argparse.ArgumentParser(
        description="One-group slab reactor flux calculator"
    )
    parser.add_argument("--length",   type=float, default=100.0,
                        help="Slab width L (cm)")
    parser.add_argument("--nodes",    type=int,   default=501,
                        help="Grid points in x")
    parser.add_argument("--D",        type=float, default=1.0,
                        help="Diffusion coefficient D (cm)")
    parser.add_argument("--Sigma_a",  type=float, default=0.01,
                        help="Absorption cross-section Σₐ (1/cm)")
    parser.add_argument("--S",        type=float, default=1.0,
                        help="Uniform source term S (n/cm³·s)")
    args = parser.parse_args()

    # Compute flux distribution
    x, phi = slab_flux(
        L=args.length,
        D=args.D,
        Sigma_a=args.Sigma_a,
        S=args.S,
        N=args.nodes
    )

    # Print peak and average flux
    print(f"Peak flux:    {phi.max():.4e}  n/cm²·s")
    print(f"Average flux: {phi.mean():.4e}  n/cm²·s\n")

    # Plot φ(x)
    plt.figure(figsize=(8, 5))
    plt.plot(x, phi, lw=2)
    plt.title("Neutron Flux Distribution in a Slab Reactor")
    plt.xlabel("Position x (cm)")
    plt.ylabel("Flux φ(x) (n/cm²·s)")
    plt.grid(linestyle="--", alpha=0.5)
    plt.tight_layout()
    plt.show()

if __name__ == "__main__":
    main()
