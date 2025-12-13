# PowerShell Image Optimization Suite

A collection of PowerShell scripts for batch image optimization using industry-standard tools (**oxipng**, **MozJPEG**, and **Gifsicle**). These scripts automate the process of finding the best compression parameters to reduce file size without compromising quality.

## 🛠 Prerequisites & Installation

To use these scripts, you must download the required binaries and place them in specific subdirectories within the script folder.

1.  **MozJPEG:** [Download from GitHub](https://github.com/garyzyg/mozjpeg-windows/releases)
2.  **oxipng:** [Download from GitHub](https://github.com/oxipng/oxipng/releases)
3.  **Gifsicle:** [Download from eternallybored.org](https://eternallybored.org/misc/gifsicle/)

**Required Directory Structure:**
Ensure your folder looks like this:

```text
/ProjectRoot
│   ├── mozjpeg/
│   │   ├── cjpeg-static.exe
│   │   └── jpegtran-static.exe
│   ├── oxipng/
│   │   └── oxipng.exe
│   ├── gifsicle/
│   │   ├── gifsicle.exe
│   │   └── gifdiff.exe
│   ├── jpg_opt.ps1
│   ├── png_opt.ps1
│   └── ... (other scripts)
```

## 🚀 Usage

Run the scripts via PowerShell. You can either specify an output directory or omit it to optimize files in place (you will be prompted to confirm replacement).

**Syntax:**

```powershell
.\<Script_Name.ps1> "<Input Path>" "<Output Path>"
# OR
.\<Script_Name.ps1> "<Input Path>"
```

**Example:**

```powershell
.\jpg_opt.ps1 "C:\Photos\Input" "C:\Photos\Optimized"
```

## 📜 Script Descriptions

| Script Name | Target | Description | Multithreading |
| :--- | :--- | :--- | :--- |
| **`jpg_opt.ps1`** | JPG, PNG, PPM, PNM, PGM, PBM, BMP, DIB, TGA, ICB, VDA, VST, RLE | **Brute-force optimization.** Tests 21 different MozJPEG parameter combinations for every file and selects the smallest result. Converts all non-JPG inputs (PNG, PPM, BMP, TGA, etc.) to highly compressed JPG format. | PS 7+ |
| **`jpg_opt_losless.ps1`** | JPG | **Lossless.** Uses `jpegtran` to optimize Huffman tables and remove metadata without changing image data. | PS 7+ |
| **`png_opt.ps1`** | PNG | **Balanced.** Uses `oxipng` with standard optimization settings. | Native\* |
| **`png_opt_slow.ps1`** | PNG | **Maximum Compression.** Uses `oxipng` with the **Zopfli** algorithm. Approx. 100x slower, but results in 2-8% smaller files. | Native\* |
| **`gif_opt_losless.ps1`** | GIF | **Lossless.** Uses `gifsicle` (O3) and verifies integrity using `gifdiff` to ensure frames are identical to the source. | Native\* |
| **`*_not_safe.ps1`** | PNG | **Aggressive/Unsafe.** Removes all chunks/metadata and uses aggressive alpha handling. **Warning:** May break transparency or prevent files from opening in strictly compliant software. | Native\* |

> \***Note on Multithreading:**
>
>   * **Native:** `oxipng` has built-in multithreading, so PNG scripts work fast on all PowerShell versions. `gifsicle` has built-in multithreading with -j but not always work good.
>   * **PS 7+:** JPG scripts utilize `ForEach-Object -Parallel` which requires **PowerShell Core 7.0** or higher for parallel processing. On older versions (PS 5.1), they will run sequentially.

## ⚠️ Important Notes

  * **Backup:** Always backup your images before running "unsafe" scripts or choosing to overwrite original files.
  * **System Language:** Scripts automatically detect system language (English/Russian) for console output.