# -*- coding: utf-8; mode: tcl; c-basic-offset: 4; indent-tabs-mode: nil; tab-width: 4; truncate-lines: t -*- vim:fenc=utf-8:et:sw=4:ts=4:sts=4
#
# This PortGroup supports the Rust language ecosystem
#
# Usage:
#
# PortGroup     rust 1.0
#
# cargo.crates \
#     foo  1.0.1  abcdef123456... \
#     bar  2.5.0  fedcba654321...
#
# The cargo.crates option expects a list with 3-tuples consisting of name,
# version, and sha256 checksum. Only sha256 is supported at this time as
# the checksum will be reused by cargo internally.
#
# The list of crates and their checksums can be found in the Cargo.lock file in
# the upstream source code. The cargo2port generator can be used to automate
# updates of this list for new releases.
#
# To get a list of these, run in worksrcdir:
#     cargo update
#     egrep -e '^(name|version|checksum) = ' Cargo.lock | perl -pe 's/^(?:name|version|checksum) = "(.+)"/$1/'
#
# https://github.com/macports/macports-contrib/tree/master/cargo2port/cargo2port.tcl
#
# If Cargo.lock references pre-release versions, or in general references
# crates not published on crates.io, but available from GitHub, also use the
# following:
#
# # download additional crates from github, not published on crates.io
# cargo.crates_github \
#    baz    author/baz  branch  abcdef12345678...commit...abcdef12345678  fedcba654321...
#

PortGroup   muniversal          1.1
PortGroup   compiler_wrapper    1.0
# ideally, we would like to add the openssl PG, however
#     its use of `option_proc` makes changing the default value of `openssl.branch` difficult, and
#     it interferes with our intended use of compiler_wrapper PG
# for now, create an option `openssl.branch` in this PG
# Cargo's interaction with OpenSSL is a bit delicate
# see, e.g., https://trac.macports.org/ticket/65011
#
# similarly for legacysupport PG

options     cargo.bin \
            cargo.home \
            cargo.crates \
            cargo.offline_cmd \
            cargo.crates_github \
            cargo.update

default     cargo.bin           {${prefix}/bin/cargo}
default     cargo.home          {${workpath}/.home/.cargo}
default     cargo.crates        {}
default     cargo.crates_github {}

# if a dependency has been patched, `--offline` might be a reasonable choice
default     cargo.offline_cmd   {--frozen}

# some packags do not provide Cargo.lock,
# so offer the option of running cargo-update
default     cargo.update        {no}

# use `--remap-path-prefix` to prevent build information from bing included installed binaries
options     rust.remap
default     rust.remap          {${cargo.home} "" ${worksrcpath} ""}

# flags to be passed to the rust compiler
# --remap-path-prefix=... is eventually added unless rust.remap is empty
options     rust.flags
default     rust.flags          {}

options     rust.upstream_deployment_target \
            rust.upstream_archs \
            rust.use_cctools \
            rust.archiver \
            rust.ranlib

# default macosx_deployment_target value of Rust function macos_default_deployment_target
# see https://github.com/rust-lang/rust/blob/master/compiler/rustc_target/src/spec/apple_base.rs
default     rust.upstream_deployment_target {[expr {${os.arch} eq "arm" ? 11.0 : 10.7}]}

# architectures for which an upstream bootstrap compiler is available
default     rust.upstream_archs     {[expr {${os.platform} eq "darwin" && ${os.major} >= 13 ? {arm64 x86_64} : {}}]}

# some tools provided by system are too old, so use MacPorts version instead
default     rust.use_cctools        {[expr {${os.platform} eq "darwin" && ${os.major} < 11 ? "yes" : "no"}]}
default     rust.archiver           {[expr {${rust.use_cctools} ? "${prefix}/bin/ar" : "/usr/bin/ar"}]}
default     rust.ranlib             {[expr {${rust.use_cctools} ? "${prefix}/bin/ranlib" : "/usr/bin/ranlib"}]}

# compiler runtime library
#     N.B.: `configure.ldflags-append {*}${rust.rt_static_libs}` might be insufficient
#     `rust.rt_static_libs` will not give the correct value until *after* the compiler is active
#     the compiler might not be active immediately if added as a dependency
options     rust.rt_static_libs
default     rust.rt_static_libs     {[rust::get_static_rutime_libraries]}

# force compiler runtime library to be included in link flags
options     rust.add_compiler_runtime
default     rust.add_compiler_runtime   {no}

# the distfiles of the main port will also be stored in this directory,
# but this is the only way to allow reusing the same crates across multiple ports.
default     dist_subdir             {[expr {[llength ${cargo.crates}] > 0 || [llength ${cargo.crates_github}] > 0 ? "cargo-crates" : ${name}}]}
default     extract.only            {[rust::disttagclean $distfiles]}

# to wrap linker, compiler_wrapper PG required existence of configure.ld
options     configure.ld
default     configure.ld            {${configure.cc}}

# Rust set its own compiler flags, so make empty by default
default     configure.cflags        {}
default     configure.cxxflags      {}
default     configure.ldflags       {[expr {${rust.add_compiler_runtime} ? ${rust.rt_static_libs} : {}} ]}
default     compiler.limit_flags    {yes}
default     configure.pipe          {no}
rename      portconfigure::should_add_stdlib  portconfigure::should_add_stdlib_real
rename      portconfigure::should_add_cxx_abi portconfigure::should_add_cxx_abi_real
proc        portconfigure::should_add_stdlib  {} {return no}
proc        portconfigure::should_add_cxx_abi {} {return no}

# enforce same compiler settings as used by rust
default compiler.cxx_standard           2017
default compiler.thread_local_storage   yes

# do not include os.major in target triplet
default     triplet.os              {${os.platform}}

# Rust does not easily pass external flags to compilers, so add them to compiler wrappers
default     compwrap.compilers_to_wrap          {cc cxx ld}
default     compwrap.ccache_supported_compilers {}

# possible OpenSSL versions: empty, 3, 1.1, and 1.0
options     openssl.branch
default     openssl.branch      {}

# utility method to get bootstrap compilers
# should only be needed by Rust/Cargo ports
proc rust.add_bootstrap_components {architectures {components {rust-std rustc cargo}}} {
    global extract.suffix os.major subport

    set version_current         1.71.1
    set version_m1              1.70.0
    set version_m2              1.69.0

    master_sites-append         https://static.rust-lang.org/dist:apple_vendor \
                                https://github.com/MarcusCalhoun-Lopez/rust/releases/download/${version_current}:macports_vendor \
                                file://[option prefix]/libexec/rust-bootstrap:transition_vendor

    if { [join [lrange [split ${subport} -] 0 1] -] eq "rust-bootstrap" } {
        set is_bootstrap        yes
    } else {
        set is_bootstrap        no
    }

    set rustc_version           ${version_m1}; # ensure value is always set (see https://trac.macports.org/ticket/65183)
    foreach arch ${architectures} {
        # rust-bootstrap requires `macosx_deployment_target` instead of `os.major`
        if { ${arch} in [option rust.upstream_archs] && [vercmp [option macosx_deployment_target] >= [option rust.upstream_deployment_target]]} {
            set build_vendor        apple
            if { ${is_bootstrap} } {
                set rustc_version   ${version_m2}
            } else {
                set rustc_version   ${version_m1}
            }
            set build_major         ""
        } elseif { ${arch} in [option rust.upstream_archs] && ${is_bootstrap} && ${subport} ne "rust-bootstrap-transition" } {
            set build_vendor        transition
            set build_major         ""
            set rustc_version       ${version_m1}
        } else {
            set build_vendor        macports
            if { ${os.major} >= 11 || [option os.platform] ne "darwin" } {
                set rustc_version   ${version_m1}+0
                set build_major     ""
            } elseif { ${os.major} >= 10 } {
                set rustc_version   ${version_m1}+0
                set build_major     10
            } elseif { ${os.major} >= 9 } {
                set rustc_version   ${version_m1}+0
                set build_major     9
            } elseif { ${os.major} >= 8 } {
                set rustc_version   ${version_m1}+0
                set build_major     8
            }
        }

        if { ${build_vendor} ne "transition" } {
            foreach component ${components} {
                set binTag          ${rustc_version}-[option triplet.cpu.${arch}]-${build_vendor}-[option triplet.os]${build_major}
                # bootstrap binaries not currently available for Tiger
                # https://trac.macports.org/ticket/65184
                if {$build_major != 8} {
                    distfiles-append    ${component}-${binTag}${extract.suffix}:${build_vendor}_vendor
                }
                # mirroring workaround for Snow Leopard i386 files
                if {[variant_exists mirror_i386] && [variant_isset mirror_i386]} {
                    set extrabintag     ${version_m1}+0-[option triplet.cpu.i386]-macports-[option triplet.os]10
                    distfiles-append    ${component}-${extrabintag}${extract.suffix}:macports_vendor
                }
            }
        } else {
            depends_extract-delete          port:rust-bootstrap-transition
            depends_extract-append          port:rust-bootstrap-transition
            depends_build-delete            port:rust-bootstrap-transition
            depends_build-append            port:rust-bootstrap-transition
            depends_skip_archcheck-delete   rust-bootstrap-transition
            depends_skip_archcheck-append   rust-bootstrap-transition

            if {[option muniversal.is_cross.[option configure.build_arch]]} {
                # if os.arch is arm and subport is rust-bootstrap-10.6, avoid
                #     Error: Cannot install rust-bootstrap-10.6 for the arch 'x86_64' because
                #     Error: its dependency rust-bootstrap-transition does not build for the required arch by default
                #     Error: and does not have a universal variant.
                known_fail                  yes
                pre-fetch {
                    ui_error "${subport} does not support cross-compilation"
                    return -code error "incompatible OS configuration"
                }
            }

            foreach component ${components} {
                set binTag          ${rustc_version}+0-[option triplet.cpu.${arch}]-${build_vendor}-[option triplet.os]${build_major}
                set distfile        [option prefix]/libexec/rust-bootstrap/${component}-${binTag}${extract.suffix}
                post-extract        "system -W \${workpath} \"\${extract.cmd} \${extract.pre_args} ${distfile} \${extract.post_args}\""
            }
        }
    }

    # upstream binaries
    checksums-append        rust-std-${version_m1}-x86_64-apple-darwin${extract.suffix} \
                            rmd160  d1620d5bcd9a5e86a4794848f547dd32484f52c1 \
                            sha256  0bce6e0abf5b7375ae4e78ec59d3036100267c300cb999dc6e665356bce6e3b2 \
                            size    44978754 \
                            rustc-${version_m1}-x86_64-apple-darwin${extract.suffix} \
                            rmd160  bfe1a33979dd6d33eae8569f52b6afbfa6cc4106 \
                            sha256  b4b6fa6605dac66c38008020ea11b59a06bcc1cdbac66a17204ff38aa7115221 \
                            size    91444261 \
                            cargo-${version_m1}-x86_64-apple-darwin${extract.suffix} \
                            rmd160  c15fad1fbf3d0da04a17d544c3e84923caab9bd5 \
                            sha256  e8f67154ae8faefb81be06b8804658cdde39d96e8fbd6b5240a9ef9d95f49f57 \
                            size    8607683 \
                            rust-std-${version_m1}-aarch64-apple-darwin${extract.suffix} \
                            rmd160  5efbab74af2376a619a84d00e6fa6bd2dc388f1b \
                            sha256  7fa4b1390784ab83cdef0b1dcacba9710024bb47867b72d09d6b9a711bebceb6 \
                            size    41922676 \
                            rustc-${version_m1}-aarch64-apple-darwin${extract.suffix} \
                            rmd160  ac2cb4cb93666d8d2e4470ae22c1fd964d285467 \
                            sha256  efad5373622c83dc301c4c045bc3b0ad5cb271409f89c839864f4c3af1510cc8 \
                            size    96608181 \
                            cargo-${version_m1}-aarch64-apple-darwin${extract.suffix} \
                            rmd160  0a99954fa31ac4527691c4d09bc2c03df0dd4138 \
                            sha256  42eee022368b143c45cd86905d1c9b5ac28fe0608288a805b508a0435c1433e6 \
                            size    8051884

    # upstream binaries
    checksums-append        rust-std-${version_m2}-x86_64-apple-darwin${extract.suffix} \
                            rmd160  53e46f3e7e148cc4860f5e752f3e2590ad3abf9c \
                            sha256  e44d71250dc5a238da0dc4784dad59d562862653adecd31ea52e0920b85c6a7c \
                            size    44783473 \
                            rustc-${version_m2}-x86_64-apple-darwin${extract.suffix} \
                            rmd160  956a17845cf43a68091011eb722c923d7f823e28 \
                            sha256  7b337037b7b7b2ec71cd369009cd94a32019466cdae56b6d6a8cfb74481a3de5 \
                            size    88715010 \
                            cargo-${version_m2}-x86_64-apple-darwin${extract.suffix} \
                            rmd160  d6bc4e1e3fd2a4f279ee9a61bbcb20c71123ee16 \
                            sha256  3ed0b5eaaf7e908f196b4882aad757cb2a623ca3c8e8e74471422df5e93ebfb0 \
                            size    7379771 \
                            rust-std-${version_m2}-aarch64-apple-darwin${extract.suffix} \
                            rmd160  200e0aaf3eab63c0b0fb4dfd8d6cbcec7688cd39 \
                            sha256  00307d648acc269a0874ba8de4f8eb3bd3b85a0f10e3da59ba1ff8c840e92b34 \
                            size    42521697 \
                            rustc-${version_m2}-aarch64-apple-darwin${extract.suffix} \
                            rmd160  0ab0a1e48871bf7f919cde6a76026a6cd3207f9d \
                            sha256  aaecbc9591591b42f02befedb5c4a04c8faeecfacbaffb5c9ee4ad1f77b0a3ed \
                            size    94232290 \
                            cargo-${version_m2}-aarch64-apple-darwin${extract.suffix} \
                            rmd160  7bbdbae8e74ed5b774c12837cee6e8446dfefdb4 \
                            sha256  b185ea41a0ad76ac23b08744732c51e4811528291f7193d612a42e3e54ecd535 \
                            size    6824595

    # MacPorts bootstrap binaries for older system
    checksums-append        rust-std-${version_m1}+0-x86_64-macports-darwin${extract.suffix} \
                            rmd160  457fee19b1250947a981f336498dafd5434070fd \
                            sha256  eff776006cef19592e41ffbc5263443ce9e6a100383e47cd71b8b8e1b0afc593 \
                            size    44835405 \
                            rustc-${version_m1}+0-x86_64-macports-darwin${extract.suffix} \
                            rmd160  13748051b3301bb41b4bc3e6f13f70d51d0f952b \
                            sha256  6884fe0de7732d23b9dd48e5a3d4346548aed88a6aeebcfeadce7aa7f66698b6 \
                            size    59051829 \
                            cargo-${version_m1}+0-x86_64-macports-darwin${extract.suffix} \
                            rmd160  6bc89b0e031cbf012a7cf9b12df5ac1d324e493f \
                            sha256  a3a3f73b5272793125bc64f35f58ad7b6914eaca10d2642b3298f7b3792dbf3a \
                            size    9932453 \
                            rust-std-${version_m1}+0-i686-macports-darwin${extract.suffix} \
                            rmd160  37155e045512352f810e8488d378dbca5933c42a \
                            sha256  75dd7eff3c4d990a4279879a0611720a39dc3c900d184867f1e63c22892ec5a9 \
                            size    44218170 \
                            rustc-${version_m1}+0-i686-macports-darwin${extract.suffix} \
                            rmd160  572d2975a03cc3f754473c0a1d2bda66b50274af \
                            sha256  f5035f3dcc619a36cd7bff92cb6a1846ecfa7bb771632c647efb58f3bb09439e \
                            size    74893342 \
                            cargo-${version_m1}+0-i686-macports-darwin${extract.suffix} \
                            rmd160  18ddfeee80b7686b9e495a735852764faf49a782 \
                            sha256  e0abceb7f07edf55a912082693dd90688545de9aaf06677e0db15544691b669d \
                            size    9798952 \
                            rust-std-${version_m1}+0-x86_64-macports-darwin10${extract.suffix} \
                            rmd160  27db2aa733e80209dbf698edc20067c68b48bf2b \
                            sha256  e0bd630e3b2494dc796f5df92897a0f7ff50f1ee8c312446d656af104ba6c265 \
                            size    44876779 \
                            rustc-${version_m1}+0-x86_64-macports-darwin10${extract.suffix} \
                            rmd160  d413bcc4ba9fabf584f7ba2ba8449b8878d9f67a \
                            sha256  fffab98ee25df2433be4369f571a2b84d5bd0e29015a3fe094bd1da761655041 \
                            size    59166376 \
                            cargo-${version_m1}+0-x86_64-macports-darwin10${extract.suffix} \
                            rmd160  8306676aee2799577fd385a43bb8fd2efff4ec7a \
                            sha256  606d333fd5e7d380cbef6dba50329f45b0d9667f5a184c067d7493ea3bf51c8d \
                            size    9956017 \
                            rust-std-${version_m1}+0-i686-macports-darwin10${extract.suffix} \
                            rmd160  2e0be41a349982ddbcb060345e28539810ac9489 \
                            sha256  ae6d00c0caaba2e624bf6cdea9054a0ba45f7016accf4916b8ed3d9a70a3f490 \
                            size    44270577 \
                            rustc-${version_m1}+0-i686-macports-darwin10${extract.suffix} \
                            rmd160  6e4443f4e02a25815f80371b210b82cb25697e5a \
                            sha256  cfbd5004f0e9306d3ea794b0237c819d7b7cfae3080f60d0515762bb416215ad \
                            size    75107810 \
                            cargo-${version_m1}+0-i686-macports-darwin10${extract.suffix} \
                            rmd160  30f0dbf3dfe74fcab3c0409f8e9a94a487a3e5a5 \
                            sha256  bf59d3b356acf089ef65d191f97c8705e88190aa35712bfd503e2a7cce0a9510 \
                            size    9829404 \
                            rust-std-${version_m1}+0-x86_64-macports-darwin9${extract.suffix} \
                            rmd160  161a128048a6c0005ecc2184dcfdb2e8375ac858 \
                            sha256  706001daf9e137acda75dd33d20b246641dbf9f6d8aad5076a24599c8e850044 \
                            size    44687581 \
                            rustc-${version_m1}+0-x86_64-macports-darwin9${extract.suffix} \
                            rmd160  312787e1b9b60deef69f7a6472acf75f049604d8 \
                            sha256  1db6b423872d0c46b62e39c4f99d8100028b89d3f668c1fbcdf4827c953c6119 \
                            size    58819501 \
                            cargo-${version_m1}+0-x86_64-macports-darwin9${extract.suffix} \
                            rmd160  e32ca8380099bab3d687ec9d6533878fad919135 \
                            sha256  b0b5b3a5382e6274ab8e9a0dff0522212bfaec4e21cc5f37f344e78093993cc5 \
                            size    9796058 \
                            rust-std-${version_m1}+0-i686-macports-darwin9${extract.suffix} \
                            rmd160  496a0012a3488e8cf59f59201ab7f1ad0eaf2fdf \
                            sha256  25198cfe531f30dc7ac1ff63c7a2283734cf43e6db01b5c5ad2739d4ae7030b0 \
                            size    44079023 \
                            rustc-${version_m1}+0-i686-macports-darwin9${extract.suffix} \
                            rmd160  998d6b5af4c9a913786898aca773d7acc5ad4888 \
                            sha256  e8964088c4d859201e23df3206667f00a4e54dfdd07bfaaadcad502dab3a0fe6 \
                            size    74812980 \
                            cargo-${version_m1}+0-i686-macports-darwin9${extract.suffix} \
                            rmd160  ca9b0fd9f2866e78d53ee35d00a5199abe51c7ca \
                            sha256  f7b17341e7711a3f8679d92533ac5ffe0791ee23f2f4aeb565e26384b787b142 \
                            size    9674221

    return                  [lindex [split ${rustc_version} +] 0]
}

####################################################################################################################################
# for building LLVM as part of building the Rust compiler
####################################################################################################################################

options     rust.llvm.legacy
default     rust.llvm.legacy        {[expr {${os.major} < 11}]}

options     rust.llvm.cflags
default     rust.llvm.cflags        {[portconfigure::configure_get_cppflags] ${configure.optflags} [expr {${rust.llvm.legacy} ? "-isystem${prefix}/include/LegacySupport" : ""}]}

options     rust.llvm.cxxflags
default     rust.llvm.cxxflags      {[portconfigure::configure_get_cppflags] ${configure.optflags} [expr {${rust.llvm.legacy} ? "-isystem${prefix}/include/LegacySupport" : ""}]}

options     rust.llvm.ldflags
default     rust.llvm.ldflags       {[portconfigure::configure_get_ldflags] [expr {${rust.llvm.legacy} ? "${prefix}/lib/libMacportsLegacySupport.a" : ""}]}

####################################################################################################################################
# utility procedures
####################################################################################################################################

# MacPorts architecture name --> Rust architecture name
proc rust.rust_arch {arch} {
    switch ${arch} {
        arm64       {return aarch64}
        i386        {return i686}
        ppc         {return powerpc}
        ppc64       {return powerpc64}
        default     {return ${arch}}
    }
}

# Rust architecture name --> MacPorts architecture name
proc rust.marcports_arch {rarch} {
    switch ${rarch} {
        aarch64     {return arm64}
        i686        {return i386}
        powerpc     {return ppc}
        powerpc64   {return ppc64}
        default     {return ${rarch}}
    }
}

####################################################################################################################################
# compatibility procedures
####################################################################################################################################
proc cargo.rust_platform {{arch ""}} {
    if {${arch} eq ""} {
        set arch [option muniversal.build_arch]
        # muniversal.build_arch is empty if we are not doing a universal build
        if {${arch} eq ""} {
            set arch [option configure.build_arch]
            if {${arch} eq ""} {
                error "No build arch configured"
            }
        }
    }
    return [option triplet.${arch}]
}

####################################################################################################################################
# internal procedures
####################################################################################################################################

namespace eval rust {}

# for symbol ___emutls_get_address (used when thread-local-storage is emulated)
#
# for Clang, provides symbol ___muloti4
# since https://github.com/rust-lang/rust/commit/8a6ff90a3a41e6ace18aeb089ea0a0eb3726dd08
#
proc rust::get_static_rutime_libraries {} {
    set libs [list ]

    if {[string match *clang* [option configure.compiler]]} {
        set libName lib/[option os.platform]/libclang_rt.osx.a
    } else {
        set libName libgcc_eh.a
    }

    if {![catch [list exec [option configure.cc] --print-search-dirs] results]} {
        foreach ln [split ${results} \n] {
            set splt [split ${ln} =]
            if {[lindex ${splt} 0] eq "libraries: "} {
                foreach dir [split [lindex ${splt} 1] :] {
                    set fl [string trimright ${dir} "/"]/${libName}
                    if {[file exists ${fl}]} {
                        lappend libs ${fl}
                    }
                }
            }
        }
    }

    return ${libs}
}

proc rust::configure_ldflags_proc {option action args} {
    if {$action ne "read"} return
    if {[option rust.add_compiler_runtime]} {
        configure.ldflags-delete    {*}[option rust.rt_static_libs]
        configure.ldflags-append    {*}[option rust.rt_static_libs]
    }
}
option_proc configure.ldflags rust::configure_ldflags_proc

# based on portextract::disttagclean from portextract.tcl
proc rust::disttagclean {list} {
    if {$list eq ""} {
        return $list
    }
    foreach fname $list {
        set name [getdistname ${fname}]

        set is_crate no
        foreach {cname cversion chksum} [option cargo.crates] {
            set cratefile ${cname}-${cversion}.crate
            if {${name} eq ${cratefile}} {
                set is_crate yes
            }
        }
        foreach {cname cgithub cbranch crevision chksum} [option cargo.crates_github] {
            set cratefile ${cname}-${crevision}.tar.gz
            if {${name} eq ${cratefile}} {
                set is_crate yes
            }
        }
        if {!${is_crate}} {
            lappend val ${name}
        }
    }
    return $val
}

proc rust::handle_crates {} {
    foreach {cname cversion chksum} [option cargo.crates] {
        # The same crate name can appear with multiple versions. Use
        # a combination of crate name and checksum as unique identifier.
        # As the :disttag cannot contain dots, the version number cannot be
        # used.
        #
        # To download the crate file curl-0.4.11.crate, the URL is
        #    https://crates.io/api/v1/crates/curl/0.4.11/download.
        # Use ?dummy= to ignore ${distfile}
        # see https://trac.macports.org/wiki/PortfileRecipes#fetchwithgetparams
        set cratefile       ${cname}-${cversion}.crate
        set cratetag        crate-${cname}-${chksum}
        distfiles-append    ${cratefile}:${cratetag}
        master_sites-append https://crates.io/api/v1/crates/${cname}/${cversion}/download?dummy=:${cratetag}
        checksums-append    ${cratefile} sha256 ${chksum}
    }

    foreach {cname cgithub cbranch crevision chksum} [option cargo.crates_github] {
        set cratefile       ${cname}-${crevision}.tar.gz
        set cratetag        crate-${cname}-${chksum}
        distfiles-append    ${cratefile}:${cratetag}
        master_sites-append https://github.com/${cgithub}/archive/${crevision}.tar.gz?dummy=:${cratetag}
        checksums-append    ${cratefile} sha256 ${chksum}
    }
}
port::register_callback rust::handle_crates

proc rust::extract_crate {cratefile} {
    set tar [findBinary tar ${portutil::autoconf::tar_path}]
    system -W "[option cargo.home]/macports" "$tar -xf [shellescape [option distpath]/${cratefile}]"
}

proc rust::write_cargo_checksum {cdirname chksum} {
    # although cargo will never see the .crate, it expects to find the sha256 checksum here
    set chkfile [open "[option cargo.home]/macports/${cdirname}/.cargo-checksum.json" "w"]
    puts $chkfile "{"
    puts $chkfile "    \"package\": ${chksum},"
    puts $chkfile "    \"files\": {}"
    puts $chkfile "}"
    close $chkfile
}

proc rust::old_macos_compatibility {cname cversion} {
    global cargo.home subport

    switch ${cname} {
        "kqueue" {
            if { [vercmp ${cversion} < 1.0.5] && "i386" in [option muniversal.architectures] } {
                # see https://gitlab.com/worr/rust-kqueue/-/merge_requests/10
                reinplace {s|all(target_os = "freebsd", target_arch = "x86")|all(any(target_os = "freebsd", target_os = "macos"), any(target_arch = "x86", target_arch = "powerpc"))|g} \
                    ${cargo.home}/macports/${cname}-${cversion}/src/time.rs
                cargo.offline_cmd-replace --frozen --offline
            }
        }
        "curl-sys" {
            if { [vercmp ${cversion} < 0.4.56] } {
                # on Mac OS X 10.6, clang exists, but `clang --print-search-dirs` returns an empty library directory
                # see https://github.com/alexcrichton/curl-rust/commit/b3a3ce876921f2e82a145d9abd539cd8f9b7ab7b
                # see https://trac.macports.org/ticket/64146#comment:16
                #
                # on other systems, we want the static library of the compiler we are using and not necessarily the system compiler
                # see https://github.com/alexcrichton/curl-rust/commit/a6969c03b1e8f66bc4c801914327176ed38f44c5
                # see https://github.com/alexcrichton/curl-rust/issues/279
                #
                # for upstream pull request, see https://github.com/alexcrichton/curl-rust/pull/451
                #
                reinplace "s|Command::new(\"clang\")|cc::Build::new().get_compiler().to_command()|g" \
                    ${cargo.home}/macports/${cname}-${cversion}/build.rs
            }
        }
    }

    # rust-bootstrap requires `macosx_deployment_target` instead of `os.major`
    if {[option os.platform] ne "darwin" || [vercmp [option macosx_deployment_target] >= 10.8]} {
        return
    }

    switch ${cname} {
        "crypto-hash" {
            # switch crypto-hash to use openssl instead of commoncrypto
            # See: https://github.com/malept/crypto-hash/issues/23
            reinplace "s|target_os = \"macos\"|target_os = \"macos_disabled\"|g" \
                ${cargo.home}/macports/${cname}-${cversion}/src/lib.rs
            reinplace "s|macos|macos_disabled|g" \
                ${cargo.home}/macports/${cname}-${cversion}/Cargo.toml
        }
        "curl-sys" {
            # curl-sys requires CCDigestGetOutputSizeFromRef which is only available since macOS 10.8
            # disable USE_SECTRANSP to avoid calling of CCDigestGetOutputSizeFromRef and use OpenSSL instead
            # See: https://github.com/alexcrichton/curl-rust/issues/429
            reinplace "s|else if target.contains(\"-apple-\")|else if target.contains(\"-apple_disabled-\")|g" \
                ${cargo.home}/macports/${cname}-${cversion}/build.rs
            reinplace "s|macos|macos_disabled|g" \
                ${cargo.home}/macports/${cname}-${cversion}/Cargo.toml
        }
        "libgit2-sys" {
            # libgit2-sys requires SSLCreateContext which is only available since macOS 10.8
            # disable GIT_SECURE_TRANSPORT to avoid calling of SSLCreateContext and use OpenSSL instead
            reinplace "s|else if target.contains(\"apple\")|else if target.contains(\"apple_disabled\")|g" \
                ${cargo.home}/macports/${cname}-${cversion}/build.rs
        }
    }

    if {[option os.platform] ne "darwin" || [vercmp [option macosx_deployment_target] >= 10.6]} {
        return
    }

    switch ${cname} {
        "notify" {
            reinplace {s|default = \["macos_fsevent"\]|default = \["macos_kqueue"\]|g} \
                ${cargo.home}/macports/${cname}-${cversion}/Cargo.toml
        }
        "cargo-util" {
            reinplace {s|#\[cfg(not(target_os = "macos"))\]|#\[cfg(not(target_os = "macos_temp"))\]|g} \
                ${cargo.home}/macports/${cname}-${cversion}/src/paths.rs
            reinplace {s|#\[cfg(target_os = "macos")\]|#\[cfg(not(target_os = "macos"))\]|g} \
                ${cargo.home}/macports/${cname}-${cversion}/src/paths.rs
            reinplace {s|#\[cfg(not(target_os = "macos_temp"))\]|#\[cfg(target_os = "macos")\]|g} \
                ${cargo.home}/macports/${cname}-${cversion}/src/paths.rs
        }
    }
}

proc rust::import_crate {cname cversion chksum cratefile} {
    global cargo.home

    ui_info "Adding ${cratefile} to cargo home"
    rust::extract_crate ${cratefile}
    rust::write_cargo_checksum "${cname}-${cversion}" "\"${chksum}\""
    rust::old_macos_compatibility ${cname} ${cversion}
}

proc rust::import_crate_github {cname cgithub crevision chksum cratefile} {
    global cargo.home

    set crepo [lindex [split ${cgithub} "/"] 1]
    set cdirname "${crepo}-${crevision}"

    ui_info "Adding ${cratefile} from github to cargo home"
    rust::extract_crate ${cratefile}
    rust::write_cargo_checksum ${cdirname} "null"
    rust::old_macos_compatibility ${cname} ${crevision}
}

post-extract {
    if {[llength ${cargo.crates}] > 0 || [llength ${cargo.crates_github}]>0} {
        file mkdir "${cargo.home}/macports"

        # avoid downloading files from online repository during build phase
        # use a replacement for crates.io
        # https://doc.rust-lang.org/cargo/reference/source-replacement.html
        set conf [open "${cargo.home}/config.toml" "w"]
        puts $conf "\[source\]"
        puts $conf "\[source.macports\]"
        puts $conf "directory = \"${cargo.home}/macports\""
        puts $conf "\[source.crates-io\]"
        puts $conf "replace-with = \"macports\""
        puts $conf "local-registry = \"/var/empty\""
        foreach {cname cgithub cbranch crevision chksum} ${cargo.crates_github} {
            puts $conf "\[source.\"https://github.com/${cgithub}\"\]"
            puts $conf "git = \"https://github.com/${cgithub}\""
            puts $conf "branch = \"${cbranch}\""
            puts $conf "replace-with = \"macports\""
        }
        close $conf

        # import all crates
        foreach {cname cversion chksum} ${cargo.crates} {
            set cratefile ${cname}-${cversion}.crate
            rust::import_crate ${cname} ${cversion} ${chksum} ${cratefile}
        }
        foreach {cname cgithub cbranch crevision chksum} ${cargo.crates_github} {
            set cratefile ${cname}-${crevision}.tar.gz
            rust::import_crate_github ${cname} ${cgithub} ${crevision} ${chksum} ${cratefile}
        }
    }

    if {${subport} ne "rust" && [join [lrange [split ${subport} -] 0 1] -] ne "rust-bootstrap"} {

        # see comment below concerning RUSTC and RUSTFLAGS

        file mkdir "${cargo.home}"
        set conf [open "${cargo.home}/config.toml" "a"]

        puts $conf "\[build\]"
        puts $conf "rustc = \"${prefix}/bin/rustc\""
        if {[option rust.flags] ne ""} {
            puts $conf "rustflags = \[\"[join [option rust.flags] {", "}]\"\]"
        }

        # be sure to include all architectures in case, e.g., a 64-bit Cargo compiles a 32-bit port
        foreach arch {arm64 x86_64 i386 ppc ppc64} {
            puts $conf "\[target.[option triplet.${arch}]\]"
            puts $conf "linker = \"[compwrap::wrap_compiler ld]\""
        }
        close $conf
    }
}

proc rust::append_envs { var {phases {configure build destroot}} } {
    foreach phase ${phases} {
        ${phase}.env-delete ${var}
        ${phase}.env-append ${var}
    }
}

# Is build caching enabled ?
# WIP for now ...
#if {[tbool configure.ccache]} {
#    # Enable sccache for rust caching
#    depends_build-append port:sccache
#    rust::append_envs    RUSTC_WRAPPER=${prefix}/bin/sccache
#    rust::append_envs    SCCACHE_CACHE_SIZE=2G
#    rust::append_envs    SCCACHE_DIR=${workpath}/.sccache
#}

proc rust::set_environment {} {
    global prefix configure.pkg_config_path
    global subport configure.build_arch configure.universal_archs

    rust::append_envs     "RUST_BACKTRACE=1"

    rust::append_envs     CC=[compwrap::wrap_compiler cc]   {build destroot}
    rust::append_envs     CXX=[compwrap::wrap_compiler cxx] {build destroot}

    if { [option openssl.branch] ne "" } {
        set openssl_ver                     [string map {. {}} [option openssl.branch]]
        rust::append_envs                   OPENSSL_DIR=${prefix}/libexec/openssl${openssl_ver}
        compiler.cpath-prepend              ${prefix}/libexec/openssl${openssl_ver}/include
        compiler.library_path-prepend       ${prefix}/libexec/openssl${openssl_ver}/lib
        configure.pkg_config_path-prepend   ${prefix}/libexec/openssl${openssl_ver}/lib/pkgconfig
    }

    # Propagate pkgconfig path to build and destroot phases as well.
    # Needed to work with openssl PG.
    if { ${configure.pkg_config_path} ne "" } {
        rust::append_envs "PKG_CONFIG_PATH=[join ${configure.pkg_config_path} :]" {build destroot}
    }

    if {${subport} ne "rust" && [join [lrange [split ${subport} -] 0 1] -] ne "rust-bootstrap"} {

        # when CARGO_BUILD_TARGET is set or `--target` is used, RUSTFLAGS and RUSTC are ignored
        #     rust::append_envs     "RUSTFLAGS=-C linker=[compwrap::wrap_compiler ld]"
        #     rust::append_envs     "RUSTC=${prefix}/bin/rustc"
        # see https://github.com/rust-lang/cargo/issues/4423

        foreach stage {configure build destroot} {
            foreach arch [option muniversal.architectures] {
                ${stage}.env.${arch}-append "CARGO_BUILD_TARGET=[option triplet.${arch}]"
            }
        }
    }
}
port::register_callback rust::set_environment

proc rust::rust_pg_callback {} {
    global  subport \
            prefix

    if { ${subport} ne "rust" && [join [lrange [split ${subport} -] 0 1] -] ne "rust-bootstrap" } {
        # port is *not* building Rust

        foreach {f s} [option rust.remap] {
            rust.flags-prepend          --remap-path-prefix=${f}=${s}
        }

        depends_build-delete            port:rust
        depends_build-append            port:rust

        if { ${subport} ne "cargo" } {
            # port is building neither Rust nor Cargo
            depends_build-delete        port:cargo
            depends_build-append        port:cargo
            depends_skip_archcheck-delete   cargo
            depends_skip_archcheck-append   cargo
        }
    } else {
        # port is building Rust

        if { [option rust.llvm.legacy] } {
            depends_build-delete        path:lib/libMacportsLegacySupport.a:legacy-support
            depends_build-append        path:lib/libMacportsLegacySupport.a:legacy-support
        }

        if { [option rust.use_cctools] } {
            depends_build-delete        port:cctools
            depends_build-append        port:cctools
            depends_skip_archcheck-delete   cctools
            depends_skip_archcheck-append   cctools
        }
    }

    if { [option openssl.branch] ne "" } {
        set openssl_ver                 [string map {. {}} [option openssl.branch]]
        depends_lib-delete              port:openssl${openssl_ver}
        depends_lib-append              port:openssl${openssl_ver}
    }

    if { [string match "macports-clang*" [option configure.compiler]] && [option os.major] < 11 } {
        # by default, ld64 uses ld64-127 when 9 <= ${os.major} < 11
        # Rust fails to build when architecture is x86_64 and ld64 uses ld64-127
        depends_build-delete            port:ld64-274
        depends_build-append            port:ld64-274
        depends_skip_archcheck-delete   ld64-274
        depends_skip_archcheck-append   ld64-274
        configure.ldflags-delete        -fuse-ld=${prefix}/bin/ld-274
        configure.ldflags-append        -fuse-ld=${prefix}/bin/ld-274
    }

    # rust-bootstrap requires `macosx_deployment_target` instead of `os.major`
    if { [option os.platform] eq "darwin" && [vercmp [option macosx_deployment_target] < 10.6]} {
        # __Unwind_RaiseException
        depends_lib-delete              port:libunwind
        depends_lib-append              port:libunwind
        configure.ldflags-delete        -lunwind
        configure.ldflags-append        -lunwind

        if { [join [lrange [split ${subport} -] 0 1] -] eq "rust-bootstrap" } {
            # Bootstrap compilers are building on newer machines to be run on older ones.
            # Use libMacportsLegacySystem.B.dylib since it is able to use the `__asm("$ld$add$os10.5$...")` trick for symbols that are part of legacy-support *only* on older systems.
            set legacyLib               libMacportsLegacySystem.B.dylib
            set dep_type                lib

            # code should mimic legacy-support
            # see https://github.com/macports/macports-ports/blob/master/devel/legacy-support/Portfile
            set max_darwin_reexport 19
            if { [option configure.build_arch] eq "arm64" || [option os.major] > ${max_darwin_reexport} } {
                # ${prefix}/lib/libMacportsLegacySystem.B.dylib does not exist
                # see https://trac.macports.org/ticket/65255
                known_fail              yes
                pre-fetch {
                    ui_error "${subport} requires libMacportsLegacySystem.B.dylib, which is provided by legacy-support"
                    return -code error "incompatible system configuration"
                }
            }
        } else {
            # Use the static library since the Rust compiler looks up certain symbols at *runtime* (e.g. `openat`).
            # Normally, we would want the additional functionality provided by MacPorts.
            # However, for reasons yet unknown, the Rust file system (sys/unix/fs.rs) functions fail when they try to use MacPorts system calls.
            set legacyLib               libMacportsLegacySupport.a
            set dep_type                build
        }

        # LLVM: CFPropertyListCreateWithStream, uuid_string_t
        # Rust: _posix_memalign, extended _realpath, _pthread_setname_np, _copyfile_state_get
        depends_${dep_type}-delete      path:lib/${legacyLib}:legacy-support
        depends_${dep_type}-append      path:lib/${legacyLib}:legacy-support
        configure.ldflags-delete        -Wl,${prefix}/lib/${legacyLib}
        configure.ldflags-append        -Wl,${prefix}/lib/${legacyLib}
    }

    # sometimes Cargo.lock does not exist
    post-extract {
        if { ${cargo.update} } {
            system -W ${worksrcpath} "${cargo.bin} --offline update"
        }
    }
}
port::register_callback rust::rust_pg_callback
