from ape import project


def main():
    manifest = project.extract_manifest()
    print("Manifest: %s" % manifest.name)
    for compiler_entry in manifest.compilers:
        compiler = project.get_compiler(compiler_entry)
        print("Compiler: %s" % compiler.name)
        print("Version: %s" % compiler.version)
        print("Path: %s" % compiler.path)
        print("")
