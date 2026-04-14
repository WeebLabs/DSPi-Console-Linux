use std::env;
use std::path::PathBuf;

fn main() {
    let crate_dir = env::var("CARGO_MANIFEST_DIR").unwrap();
    let output_dir = PathBuf::from(&crate_dir).join("..").join("include");

    std::fs::create_dir_all(&output_dir).expect("failed to create include/");

    cbindgen::Builder::new()
        .with_crate(&crate_dir)
        .with_config(cbindgen::Config::from_file("cbindgen.toml").unwrap())
        .generate()
        .expect("cbindgen failed")
        .write_to_file(output_dir.join("dspi_core.h"));
}
