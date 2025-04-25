"""

Usage example:
    python newton_fractal.py \
        --poly "z**3 - 1" \
        --dpoly "3*z**2" \
        --xmin -1.5 --xmax 1.5 \
        --ymin -1.5 --ymax 1.5 \
        --width 1000 --height 1000 \
        --max-iter 50 \
        --tol 1e-6
"""

import numpy as np
import matplotlib.pyplot as plt
import argparse
import time

def newton_iteration(z: complex, f, df, max_iter: int, tol: float):
    """
    Apply Newton's method to a starting point z for up to max_iter iterations.

    z_{n+1} = z_n - f(z_n) / f'(z_n)

    Parameters:
        z         Initial complex guess.
        f         Function f(z), the polynomial.
        df        Derivative f'(z).
        max_iter  Maximum Newton steps.
        tol       Convergence tolerance (|f(z)| < tol).

    Returns:
        root      The converged value (or last iterate).
        n         Number of iterations used.
    """
    for n in range(1, max_iter + 1):
        dz = f(z) / df(z)
        z -= dz
        if abs(dz) < tol:
            break
    return z, n

def generate_newton_fractal(f, df, roots, xmin, xmax, ymin, ymax,
                            width, height, max_iter, tol):
    """
    Create a 2D array describing convergence of each pixel to a root index.

    Parameters:
        f, df       Functions defining the polynomial and its derivative.
        roots       List of known roots to identify convergence.
        xmin,xmax   Real-axis bounds.
        ymin,ymax   Imag-axis bounds.
        width       Output image width in pixels.
        height      Output image height in pixels.
        max_iter    Maximum Newton iterations.
        tol         Convergence tolerance.

    Returns:
        root_index_map   2D int array: index of root each point converges to.
        iter_count_map   2D int array: number of iterations taken.
    """
    real_vals = np.linspace(xmin, xmax, width)
    imag_vals = np.linspace(ymin, ymax, height)
    root_index_map = np.zeros((height, width), dtype=int)
    iter_count_map = np.zeros((height, width), dtype=int)

    # For each pixel, perform Newton's method
    for i, y in enumerate(imag_vals):
        for j, x in enumerate(real_vals):
            z0 = complex(x, y)
            z, n = newton_iteration(z0, f, df, max_iter, tol)
            # Determine which known root is closest
            distances = [abs(z - r) for r in roots]
            root_index = int(np.argmin(distances))
            root_index_map[i, j] = root_index
            iter_count_map[i, j] = n

    return root_index_map, iter_count_map

def plot_newton_fractal(root_index_map, iter_count_map,
                        xmin, xmax, ymin, ymax, roots, max_iter):
    """
    Plot the Newton fractal by combining root indices and iteration counts.

    Parameters:
        root_index_map  2D array of root indices per pixel.
        iter_count_map  2D array of iteration counts.
        xmin,xmax       Bounds for axis labels.
        ymin,ymax
        roots           List of roots (for title).
        max_iter        Maximum iterations (for colour scaling).
    """
    height, width = root_index_map.shape

    # Construct an RGB image: Hues by root index, brightness by iteration speed
    hsv = np.zeros((height, width, 3), dtype=float)
    hsv[..., 0] = root_index_map / len(roots)               # hue channel
    hsv[..., 1] = 1.0                                      # full saturation
    # Value (brightness): normalized inverse iteration count
    hsv[..., 2] = 1.0 - iter_count_map / max_iter

    # Convert HSV to RGB for display
    rgb = plt.cm.hsv(hsv[..., 0])
    rgb[..., :3] = hsv_to_rgb(hsv)

    plt.figure(figsize=(10, 8))
    plt.imshow(rgb, extent=[xmin, xmax, ymin, ymax], origin='lower')
    plt.title(f"Newton Fractal for roots {', '.join(str(r) for r in roots)}")
    plt.xlabel("Re")
    plt.ylabel("Im")
    plt.tight_layout()
    plt.show()

def hsv_to_rgb(hsv):
    """
    Manually convert an HSV image array to RGB.
    hsv: array shape (..., 3) with H, S, V in [0,1].
    Returns RGB array shape (..., 4) as given by matplotlib conventions.
    """
    # use matplotlib's conversion under the hood for convenience
    import matplotlib.colors as mcolors
    flat = hsv.reshape(-1, 3)
    rgb_flat = mcolors.hsv_to_rgb(flat)
    # Append an alpha channel of 1.0
    alpha = np.ones((rgb_flat.shape[0], 1))
    rgba_flat = np.hstack([rgb_flat, alpha])
    return rgba_flat.reshape(*hsv.shape[:-1], 4)

def parse_polynomial(poly_str, dpoly_str):
    """
    Build Python callable f(z) and f'(z) from string expressions.
    Users supply `z**3 - 1` and `3*z**2`, etc.
    """
    def f(z):
        return eval(poly_str, {"z": z, "np": np})
    def df(z):
        return eval(dpoly_str, {"z": z, "np": np})
    return f, df

def main():
    """
    Parse command-line arguments, generate and plot the Newton fractal.
    Measures and prints computation time.
    """
    parser = argparse.ArgumentParser(
        description="Extensive Newton Fractal Generator and Visualizer"
    )
    parser.add_argument("--poly",   type=str, default="z**3 - 1",
                        help="Polynomial f(z), e.g. 'z**3 - 1'")
    parser.add_argument("--dpoly",  type=str, default="3*z**2",
                        help="Derivative f'(z), e.g. '3*z**2'")
    parser.add_argument("--roots", nargs="+", default=["1", 
                        "(-1+1j*np.sqrt(3))/2", "(-1-1j*np.sqrt(3))/
