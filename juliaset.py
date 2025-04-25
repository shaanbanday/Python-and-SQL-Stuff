import numpy as np
import matplotlib.pyplot as plt
import time
import argparse

def julia(z: complex, c: complex, max_iter: int) -> int:
    """
    Compute the escape iteration count for a Julia set at point z, with constant c.
    The iteration is z_{n+1} = z_n^2 + c.
    Return the iteration when |z| > 2, or max_iter if it never escapes.
    """
    for n in range(max_iter):
        z = z*z + c
        # use squared magnitude to avoid costly sqrt
        if (z.real*z.real + z.imag*z.imag) > 4.0:
            return n
    return max_iter

def generate_julia(xmin: float, xmax: float,
                   ymin: float, ymax: float,
                   width: int, height: int,
                   c: complex, max_iter: int) -> np.ndarray:
    """
    Build a 2D array of iteration counts for each pixel in the complex plane.
    
    Parameters:
      xmin, xmax: bounds on the real axis
      ymin, ymax: bounds on the imaginary axis
      width, height: image resolution in pixels
      c: complex constant defining the Julia set
      max_iter: maximum number of iterations per point
    
    Returns:
      A NumPy array of shape (height, width) with escape iteration counts.
    """
    # create evenly spaced arrays for real and imaginary axes
    real_vals = np.linspace(xmin, xmax, width)
    imag_vals = np.linspace(ymin, ymax, height)
    julia_set = np.zeros((height, width), dtype=int)
    
    # compute escape count for each pixel
    for i, y in enumerate(imag_vals):
        for j, x in enumerate(real_vals):
            z0 = complex(x, y)
            julia_set[i, j] = julia(z0, c, max_iter)
    
    return julia_set

def plot_julia(julia_set: np.ndarray,
               xmin: float, xmax: float,
               ymin: float, ymax: float,
               c: complex) -> None:
    """
    Render the Julia set using matplotlib.
    
    Parameters:
      julia_set: 2D array of iteration counts
      xmin, xmax, ymin, ymax: axis bounds for labelling
      c: complex constant used (for title)
    """
    plt.figure(figsize=(10, 8))
    plt.imshow(
        julia_set,
        extent=[xmin, xmax, ymin, ymax],
        origin='lower',
        interpolation='bicubic'
    )
    plt.title(f"Julia Set for c = {c.real:.3f} {'+' if c.imag>=0 else '-'} {abs(c.imag):.3f}i")
    plt.xlabel("Re")
    plt.ylabel("Im")
    plt.tight_layout()
    plt.show()

def main():
    """
    Entry point: parse arguments, generate the Julia grid, time it, and plot.
    """
    parser = argparse.ArgumentParser(
        description="Extensive Julia Set Generator and Visualizer"
    )
    parser.add_argument("--xmin", type=float, default=-1.5,
                        help="Min real-axis value")
    parser.add_argument("--xmax", type=float, default= 1.5,
                        help="Max real-axis value")
    parser.add_argument("--ymin", type=float, default=-1.5,
                        help="Min imaginary-axis value")
    parser.add_argument("--ymax", type=float, default= 1.5,
                        help="Max imaginary-axis value")
    parser.add_argument("--width", type=int, default=1000,
                        help="Image width in pixels")
    parser.add_argument("--height", type=int, default=1000,
                        help="Image height in pixels")
    parser.add_argument("--creal", type=float, default=-0.8,
                        help="Real part of Julia constant c")
    parser.add_argument("--cimag", type=float, default= 0.156,
                        help="Imaginary part of Julia constant c")
    parser.add_argument("--max-iter", type=int, default=300,
                        help="Max iterations per point")
    
    args = parser.parse_args()
    
    # combine real and imaginary into one complex constant
    c = complex(args.creal, args.cimag)
    
    print(f"Generating Julia set for c = {c} "
          f"at {args.width}×{args.height}, max_iter={args.max_iter}...")
    start = time.time()
    jset = generate_julia(
        args.xmin, args.xmax, args.ymin, args.ymax,
        args.width, args.height, c, args.max_iter
    )
    elapsed = time.time() - start
    print(f"Completed in {elapsed:.2f} seconds. Rendering now...")
    
    plot_julia(jset, args.xmin, args.xmax, args.ymin, args.ymax, c)

if __name__ == "__main__":
    main()
