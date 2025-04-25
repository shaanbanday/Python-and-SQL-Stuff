#!/usr/bin/env python3
"""
A simple on-power refuelling simulator for a CANDU reactor core.
Models burnup of fuel bundles, selects highest-burnup channels each step,
and replaces spent bundles while tracking core performance metrics.
"""

import numpy as np
import matplotlib.pyplot as plt
import argparse
import time

class FuelBundle:
    """Represents a single fuel bundle, tracking its burnup (MWd/kgU)."""
    def __init__(self):
        self.burnup = 0.0

class FuelChannel:
    """One CANDU fuel channel holding a single FuelBundle."""
    def __init__(self):
        self.bundle = FuelBundle()

    def burn(self, rate: float):
        """Increment burnup by `rate` each time step."""
        self.bundle.burnup += rate

    def refuel(self) -> float:
        """
        Replace this channel’s bundle with fresh fuel.
        Returns the burnup of the discharged bundle.
        """
        discharged = self.bundle.burnup
        self.bundle = FuelBundle()
        return discharged

class Core:
    """The reactor core as a collection of FuelChannels."""
    def __init__(self, num_channels: int):
        self.channels = [FuelChannel() for _ in range(num_channels)]

    def burn_all(self, rate: float):
        """Burn every channel by the given rate."""
        for ch in self.channels:
            ch.burn(rate)

    def average_burnup(self) -> float:
        """Compute and return the average burnup across all channels."""
        burnups = [ch.bundle.burnup for ch in self.channels]
        return float(np.mean(burnups))

class FuellingMachine:
    """
    Simulates the on-power fuelling machine.
    At each step it refuels the highest-burnup bundles.
    """
    def __init__(self):
        self.total_refuel_count = 0
        self.discharged_burnups = []

    def refuel_core(self, core: Core, bundles_per_step: int):
        """
        Find `bundles_per_step` channels with highest burnup
        and refuel them.
        """
        # Pair channel index with its bundle burnup
        indexed = list(enumerate(core.channels))
        # Sort by burnup descending
        indexed.sort(key=lambda x: x[1].bundle.burnup, reverse=True)
        # Refuel top N
        for idx, channel in indexed[:bundles_per_step]:
            burned = channel.refuel()
            self.discharged_burnups.append(burned)
            self.total_refuel_count += 1

class CANDUSimulator:
    """
    Orchestrates core burnup and refuelling over a series of time steps,
    and records performance metrics.
    """
    def __init__(self, num_channels: int, burn_rate: float,
                 bundles_per_step: int, total_steps: int):
        self.core = Core(num_channels)
        self.fm = FuellingMachine()
        self.burn_rate = burn_rate
        self.bundles_per_step = bundles_per_step
        self.total_steps = total_steps

        # Data storage
        self.avg_burnup = []       # average core burnup each step
        self.refuel_events = []    # cumulative refuels each step

    def run(self):
        """Run the simulation: burn then refuel each time step."""
        for step in range(1, self.total_steps + 1):
            # Burn all bundles
            self.core.burn_all(self.burn_rate)
            # Refuel highest-burnup bundles
            self.fm.refuel_core(self.core, self.bundles_per_step)
            # Record metrics
            self.avg_burnup.append(self.core.average_burnup())
            self.refuel_events.append(self.fm.total_refuel_count)

def main():
    parser = argparse.ArgumentParser(
        description="CANDU On-Power Refuelling Simulator"
    )
    parser.add_argument("--channels", type=int, default=380,
                        help="Number of fuel channels in the core")
    parser.add_argument("--burn-rate", type=float, default=1.0,
                        help="Burnup rate per channel per step (MWd/kgU)")
    parser.add_argument("--bundles-per-step", type=int, default=3,
                        help="How many bundles to refuel each step")
    parser.add_argument("--steps", type=int, default=500,
                        help="Total number of time steps to simulate")
    args = parser.parse_args()

    print("Starting simulation with parameters:")
    print(f"  Channels:          {args.channels}")
    print(f"  Burn rate:         {args.burn_rate} MWd/kgU per step")
    print(f"  Bundles/step:      {args.bundles_per_step}")
    print(f"  Total steps:       {args.steps}")

    sim = CANDUSimulator(
        num_channels=args.channels,
        burn_rate=args.burn_rate,
        bundles_per_step=args.bundles_per_step,
        total_steps=args.steps
    )

    start = time.time()
    sim.run()
    elapsed = time.time() - start
    print(f"Simulation completed in {elapsed:.2f} seconds.\n")

    # Plot average burnup over time
    plt.figure(figsize=(10, 5))
    plt.plot(range(1, args.steps + 1), sim.avg_burnup, lw=2)
    plt.title("Average Core Burnup Over Time")
    plt.xlabel("Time Step")
    plt.ylabel("Average Burnup (MWd/kgU)")
    plt.grid(True, linestyle='--', alpha=0.5)
    plt.tight_layout()
    plt.show()

    # Plot histogram of discharged burnups
    plt.figure(figsize=(6, 4))
    plt.hist(sim.fm.discharged_burnups, bins=20, edgecolor='black')
    plt.title("Distribution of Discharged Bundle Burnups")
    plt.xlabel("Burnup at Discharge (MWd/kgU)")
    plt.ylabel("Count")
    plt.tight_layout()
    plt.show()

if __name__ == "__main__":
    main()
