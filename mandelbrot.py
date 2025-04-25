import numpy as np
import matplotlib.pyplot as plt
import time
import argparse

def mandelbrot(c: complex, max_iter: int) -> int:
    """
    Compute the escape iteration count for a point c in the complex plane.
    The iteration is z_{n+1} = z_n^2 + c, starting at z_0 = 0.
    Return the iteration number when |z| > 2, or max_iter if it never escapes.
    """
    z = 0 + 0j
    for n in range(max_iter):
        z = z*z + c
        # Check squared magnitude to avoid a sqrt
        if (z.real*z.real + z.imag*z.imag) > 4.0:
            return n
    return max_iter

def generate_mandelbrot(xmin: float, xmax: float,
                        ymin: float, ymax: float,
                        width: int, height: int,
                        max_iter: int) -> np.ndarray:
    """
    Generate a 2D array of iteration counts for each pixel in the specified region.
    
    Parameters:
      xmin, xmax: bounds on the real axis
      ymin, ymax: bounds on the imaginary axis
      width, height: resolution of the output image
      max_iter: maximum number of iterations per point
    
    Returns:
      A NumPy array of shape (height, width) with escape iteration counts.
    """
    real_vals = np.linspace(xmin, xmax, width)
    imag_vals = np.linspace(ymin, ymax, height)
    mandelbrot_set = np.zeros((height, width), dtype=int)
    
    # Loop over each pixel coordinate
    for i, y in enumerate(imag_vals):
        for j, x in enumerate(real_vals):
            c = complex(x, y)
            mandelbrot_set[i, j] = mandelbrot(c, max_iter)
    
    return mandelbrot_set

def plot_mandelbrot(mandelbrot_set: np.ndarray,
                    xmin: float, xmax: float,
                    ymin: float, ymax: float) -> None:
    """
    Plot the Mandelbrot set array using matplotlib.
    
    Parameters:
      mandelbrot_set: 2D array of iteration counts
      xmin, xmax, ymin, ymax: bounds for axis labels
    """
    plt.figure(figsize=(10, 8))
    plt.imshow(
        mandelbrot_set,
        extent=[xmin, xmax, ymin, ymax],
        origin='lower',
        interpolation='bicubic'
    )
    plt.title("Mandelbrot Set")
    plt.xlabel("Re")
    plt.ylabel("Im")
    plt.tight_layout()
    plt.show()

def main():
    """
    Parse command-line arguments, generate the Mandelbrot array, and plot it.
    Also prints timing information.
    """
    parser = argparse.ArgumentParser(
        description="Extensive Mandelbrot Set Generator and Visualizer"
    )
    parser.add_argument("--xmin", type=float, default=-2.5,
                        help="Minimum real-axis value")
    parser.add_argument("--xmax", type=float, default=1.5,
                        help="Maximum real-axis value")
    parser.add_argument("--ymin", type=float, default=-2.0,
                        help="Minimum imaginary-axis value")
    parser.add_argument("--ymax", type=float, default=2.0,
                        help="Maximum imaginary-axis value")
    parser.add_argument("--width", type=int, default=1000,
                        help="Image width in pixels")
    parser.add_argument("--height", type=int, default=1000,
                        help="Image height in pixels")
    parser.add_argument("--max-iter", type=int, default=256,
                        help="Max iterations per point")
    
    args = parser.parse_args()
    
    print(f"Generating Mandelbrot set with resolution "
          f"{args.width}×{args.height}, max_iter={args.max_iter}...")
    start = time.time()
    mb = generate_mandelbrot(
        args.xmin, args.xmax, args.ymin, args.ymax,
        args.width, args.height, args.max_iter
    )
    elapsed = time.time() - start
    print(f"Done in {elapsed:.2f} seconds. Now plotting...")
    
    plot_mandelbrot(mb, args.xmin, args.xmax, args.ymin, args.ymax)

if __name__ == "__main__":
    main()
