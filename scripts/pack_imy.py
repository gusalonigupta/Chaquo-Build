#!/usr/bin/env python3
"""
pack_imy.py <pip_install_output_dir> <out_dir> <py_short> "<abi list space separated>"

- Zips each subdir under pip_install output into requirements-<name>.imy
- Copies any .so artifacts into native/<abi> under out_dir (so loader can extract them)
- Writes a small build.json (python_version, assets->sha1) and creates a bundle zip
"""
import os, sys, zipfile, hashlib, json, shutil, time

def sha1_of_file(path):
    h = hashlib.sha1()
    with open(path, "rb") as f:
        while True:
            b = f.read(1024*1024)
            if not b:
                break
            h.update(b)
    return h.hexdigest()

def zip_dir(src_dir, out_zip):
    with zipfile.ZipFile(out_zip, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for root, dirs, files in os.walk(src_dir):
            for fn in files:
                full = os.path.join(root, fn)
                arc = os.path.relpath(full, src_dir)
                zf.write(full, arc)
    return out_zip

if __name__ == "__main__":
    if len(sys.argv) < 5:
        print("Usage: pack_imy.py <pip_target_dir> <out_dir> <py_short> \"abi1 abi2 ...\"")
        sys.exit(2)
    src = sys.argv[1]
    out = sys.argv[2]
    py_short = sys.argv[3]
    abis = sys.argv[4].split()

    os.makedirs(out, exist_ok=True)

    assets = {}
    # zip each subdir in src -> requirements-<name>.imy
    for name in sorted(os.listdir(src)):
        full = os.path.join(src, name)
        if not os.path.isdir(full):
            continue
        zipname = f"requirements-{name}.imy"
        outzip = os.path.join(out, zipname)
        print("Zipping", full, "->", outzip)
        zip_dir(full, outzip)
        assets[zipname] = sha1_of_file(outzip)

    # collect .so for ABIs (copy into native/<abi>/)
    native_out_base = os.path.join(out, "native")
    for abi in abis:
        src_abi_dir = os.path.join(src, abi)
        target_abi_dir = os.path.join(native_out_base, abi)
        if os.path.isdir(src_abi_dir):
            os.makedirs(target_abi_dir, exist_ok=True)
            for root, dirs, files in os.walk(src_abi_dir):
                for fn in files:
                    if fn.endswith(".so"):
                        src_file = os.path.join(root, fn)
                        dst_file = os.path.join(target_abi_dir, fn)
                        print("Copying native:", src_file, "->", dst_file)
                        shutil.copy2(src_file, dst_file)
                        assets[os.path.join("native", abi, fn)] = sha1_of_file(dst_file)

    # also copy any .so inside 'common' or other package dirs
    for root, dirs, files in os.walk(src):
        for fn in files:
            if fn.endswith(".so"):
                rel = os.path.relpath(root, src)
                # put under native/common if ABI not known
                dst_dir = os.path.join(native_out_base, "common")
                os.makedirs(dst_dir, exist_ok=True)
                dst_file = os.path.join(dst_dir, fn)
                src_file = os.path.join(root, fn)
                if not os.path.exists(dst_file):
                    print("Copying common .so:", src_file, "->", dst_file)
                    shutil.copy2(src_file, dst_file)
                    assets[os.path.join("native", "common", fn)] = sha1_of_file(dst_file)

    # write build.json (minimal)
    build_json = {
        "python_version": py_short,
        "assets": assets,
        "extract_packages": []
    }
    with open(os.path.join(out, "build.json"), "w") as f:
        json.dump(build_json, f, indent=2)

    # produce a single bundle zip containing all generated files
    bundle_name = f"bundle-py{py_short}-{int(time.time())}.zip"
    bundle_path = os.path.join(out, bundle_name)
    print("Creating bundle zip:", bundle_path)
    with zipfile.ZipFile(bundle_path, "w", compression=zipfile.ZIP_DEFLATED) as bz:
        for root, dirs, files in os.walk(out):
            for fn in files:
                # don't include the bundle itself if running in same dir
                full = os.path.join(root, fn)
                if full == bundle_path:
                    continue
                arc = os.path.relpath(full, out)
                bz.write(full, arc)

    assets[bundle_name] = sha1_of_file(bundle_path)
    # update build.json to include bundle hash
    with open(os.path.join(out, "build.json"), "w") as f:
        json.dump(build_json, f, indent=2)

    print("Wrote artifacts in:", out)
    print("Bundle:", bundle_path)