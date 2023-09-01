const std = @import("std");
const builtin = @import("builtin");
const vkgen = @import("deps/vulkan-zig/generator/index.zig");
const AssetStep = @import("src/build/AssetStep.zig");

const pkgs = struct {
    const network = .{
        .name = "network",
        .path = std.Build.LazyPath.relative("./deps/zig-network/network.zig"),
    };

    const args = .{
        .name = "args",
        .path = std.Build.LazyPath.relative("./deps/zig-args/args.zig"),
    };

    const pixel_draw = .{
        .name = "pixel_draw",
        .path = std.Build.LazyPath.relative("./deps/pixel_draw/src/pixel_draw_module.zig"),
    };

    const zwl = .{
        .name = "zwl",
        .path = std.Build.LazyPath.relative("./deps/zwl/src/zwl.zig"),
    };

    const painterz = .{
        .name = "painterz",
        .path = std.Build.LazyPath.relative("./deps/painterz/painterz.zig"),
    };

    const zlm = .{
        .name = "zlm",
        .path = std.Build.LazyPath.relative("./deps/zlm/zlm.zig"),
    };

    const wavefront_obj = .{
        .name = "wavefront-obj",
        .path = std.Build.LazyPath.relative("./deps/wavefront-obj/wavefront-obj.zig"),
        .dependencies = &.{
            zlm,
        },
    };

    const zzz = .{
        .name = "zzz",
        .path = std.Build.LazyPath.relative("./deps/zzz/src/main.zig"),
    };

    const gl = .{
        .name = "gl",
        .path = std.Build.LazyPath.relative("./deps/opengl/gl_3v3_with_exts.zig"),
    };

    const zigimg = .{
        .name = "zigimg",
        .path = std.Build.LazyPath.relative("./deps/zigimg/zigimg.zig"),
    };

    const soundio = .{
        .name = "soundio",
        .path = std.Build.LazyPath.relative("./deps/soundio.zig/soundio.zig"),
    };
};

const vk_xml_path = "deps/Vulkan-Docs/xml/vk.xml";

const State = enum {
    create_server,
    create_sp_game,
    credits,
    gameplay,
    join_game,
    main_menu,
    options,
    pause_menu,
    splash,
    demo_pause,
};

const RenderBackend = enum {
    /// basic software rendering
    software,

    /// high-performance desktop rendering
    vulkan,

    /// OpenGL based rendering backend
    opengl,

    /// basic rendering backend for mobile devices and embedded stuff like Raspberry PI
    opengl_es,

    /// raytracing backend planned by Snektron
    vulkan_rt,
};

const AudioConfig = struct {
    jack: bool = false,
    pulseaudio: bool,
    alsa: bool,
    coreaudio: bool,
    wasapi: bool,
};

fn addClientPackages(
    b: *std.build.Builder,
    exe: *std.Build.Step.Compile,
    target: std.zig.CrossTarget,
    render_backend: RenderBackend,
    gen_vk: *vkgen.VkGenerateStep,
    resources: AssetStep.Pkg,
) void {
    const args_module = b.createModule(.{
        .source_file = pkgs.args.path,
        .dependencies = &.{},
    });

    const network_module = b.createModule(.{
        .source_file = pkgs.network.path,
        .dependencies = &.{},
    });

    const zwl_module = b.createModule(.{
        .source_file = pkgs.zwl.path,
        .dependencies = &.{},
    });

    const zlm_module = b.createModule(.{
        .source_file = pkgs.zlm.path,
        .dependencies = &.{},
    });

    const zzz_module = b.createModule(.{
        .source_file = pkgs.zzz.path,
        .dependencies = &.{},
    });

    const resources_module = b.createModule(.{
        .source_file = std.Build.LazyPath.relative(resources.path),
        .dependencies = &.{},
    });

    const soundio_module = b.createModule(.{
        .source_file = pkgs.soundio.path,
        .dependencies = &.{},
    });

    exe.addModule(pkgs.network.name, network_module);
    exe.addModule(pkgs.args.name, args_module);
    exe.addModule(pkgs.zwl.name, zwl_module);
    exe.addModule(pkgs.zlm.name, zlm_module);
    exe.addModule(pkgs.zzz.name, zzz_module);
    exe.addModule(resources.name, resources_module);
    exe.addModule(pkgs.soundio.name, soundio_module);

    switch (render_backend) {
        .vulkan, .vulkan_rt => {
            exe.step.dependOn(&gen_vk.step);
            exe.addModule("vulkan", gen_vk.getModule());
            exe.linkLibC();

            if (target.isLinux()) {
                exe.linkSystemLibrary("X11");
            } else {
                @panic("vulkan/vulkan_rt not yet implemented yet for this target");
            }
        },
        .software => {
            const pixel_draw_module = b.createModule(.{
                .source_file = pkgs.pixel_draw.path,
                .dependencies = &.{},
            });

            const painterz_module = b.createModule(.{
                .source_file = pkgs.painterz.path,
                .dependencies = &.{},
            });

            exe.addModule(pkgs.pixel_draw.name, pixel_draw_module);
            exe.addModule(pkgs.painterz.name, painterz_module);
        },
        .opengl_es => {
            // TODO
            @panic("opengl_es is not implementated yet");
        },
        .opengl => {
            const gl_module = b.createModule(.{
                .source_file = pkgs.gl.path,
                .dependencies = &.{},
            });

            exe.addModule(pkgs.gl.name, gl_module);
            if (target.isWindows()) {
                exe.linkSystemLibrary("opengl32");
            } else {
                exe.linkLibC();
                exe.linkSystemLibrary("X11");
                exe.linkSystemLibrary("GL");
            }
        },
    }
}

pub fn build(b: *std.build.Builder) !void {
    // workaround for windows not having visual studio installed
    // (makes .gnu the default target)
    const native_target = if (builtin.os.tag != .windows)
        std.zig.CrossTarget{}
    else
        std.zig.CrossTarget{ .abi = .gnu };

    const target = b.standardTargetOptions(.{
        .default_target = native_target,
    });
    const mode = b.standardOptimizeOption(.{});

    const default_port = b.option(
        u16,
        "default-port",
        "The port the game will use as its default port",
    ) orelse 3315;
    const initial_state = b.option(
        State,
        "initial-state",
        "The initial state of the game. This is only relevant for debugging.",
    ) orelse .splash;
    const enable_frame_counter = b.option(
        bool,
        "enable-fps-counter",
        "Enables the FPS counter as an overlay.",
    ) orelse (mode == .Debug);
    const render_backend = b.option(
        RenderBackend,
        "renderer",
        "Selects the rendering backend which the game should use to render",
    ) orelse .software;
    const embed_resources = b.option(
        bool,
        "embed-resources",
        "When set, the resources will be embedded into the binary.",
    ) orelse false;

    const debug_tools = b.option(
        bool,
        "debug-tools",
        "When set, the tools will be compiled in Debug mode, ReleaseSafe otherwise.",
    ) orelse false;

    const tool_mode: std.builtin.OptimizeMode = if (debug_tools)
        .Debug
    else
        .ReleaseSafe;

    var audio_config = AudioConfig{
        .jack = b.option(bool, "jack", "Enables/disables the JACK backend.") orelse false,
        .pulseaudio = b.option(bool, "pulseaudio", "Enables/disables the pulseaudio backend.") orelse target.isLinux(),
        .alsa = b.option(bool, "alsa", "Enables/disables the alsa backend.") orelse target.isLinux(),
        .coreaudio = b.option(bool, "coreaudio", "Enables/disables the CoreAudio backend.") orelse target.isDarwin(),
        .wasapi = b.option(bool, "wasapi", "Enables/disables the WASAPI backend.") orelse target.isWindows(),
    };

    if (target.isLinux() and !target.isGnuLibC() and (render_backend == .vulkan or render_backend == .opengl or render_backend == .opengl_es)) {
        @panic("OpenGL, Vulkan and OpenGL ES require linking against glibc, musl is not supported!");
    }

    const test_step = b.step("test", "Runs the test suite for all source filess");

    const gen_vk = vkgen.VkGenerateStep.create(b, vk_xml_path);

    const args_module = b.createModule(.{
        .source_file = pkgs.args.path,
        .dependencies = &.{},
    });

    const zlm_module = b.createModule(.{
        .source_file = pkgs.zlm.path,
        .dependencies = &.{},
    });

    const wavefront_obj_module = b.createModule(.{
        .source_file = pkgs.wavefront_obj.path,
        .dependencies = &.{
            .{ .name = pkgs.zlm.name, .module = zlm_module },
        },
    });

    const zigimg_module = b.createModule(.{
        .source_file = pkgs.zlm.path,
        .dependencies = &.{},
    });

    const asset_gen_step = blk: {
        const obj_conv = b.addExecutable(.{
            .name = "obj-conv",
            .root_source_file = std.Build.LazyPath.relative("src/tools/obj-conv.zig"),
            .target = native_target,
            .optimize = tool_mode,
        });
        obj_conv.addModule(pkgs.args.name, args_module);
        obj_conv.addModule(pkgs.zlm.name, zlm_module);
        obj_conv.addModule(pkgs.wavefront_obj.name, wavefront_obj_module);

        const tex_conv = b.addExecutable(.{
            .name = "tex-conv",
            .root_source_file = std.Build.LazyPath.relative("src/tools/tex-conv.zig"),
            .target = native_target,
            .optimize = tool_mode,
        });
        tex_conv.addModule(pkgs.args.name, args_module);
        tex_conv.addModule(pkgs.zigimg.name, zigimg_module);
        tex_conv.linkLibC();

        const snd_conv = b.addExecutable(.{
            .name = "snd-conv",
            .root_source_file = std.Build.LazyPath.relative("src/tools/snd-conv.zig"),
            .target = native_target,
            .optimize = tool_mode,
        });
        snd_conv.addModule(pkgs.args.name, args_module);
        snd_conv.linkLibC();

        const tools_step = b.step("tools", "Compiles all tools required in the build process");
        tools_step.dependOn(&obj_conv.step);
        tools_step.dependOn(&tex_conv.step);
        tools_step.dependOn(&snd_conv.step);

        const asset_gen_step = try AssetStep.create(b, embed_resources, .{
            .obj_conv = obj_conv,
            .tex_conv = tex_conv,
            .snd_conv = snd_conv,
        });

        try asset_gen_step.addResources("assets-in");

        const assets_step = b.step("assets", "Compiles all assets to their final format");
        assets_step.dependOn(&asset_gen_step.step);

        break :blk asset_gen_step;
    };

    const libsoundio = blk: {
        const root = "./deps/libsoundio";
        const lib = b.addStaticLibrary(.{
            .name = "soundio",
            .target = target,
            .optimize = mode,
        });

        const cflags = [_][]const u8{
            "-std=c11",
            "-fvisibility=hidden",
            "-Wall",
            "-Werror=strict-prototypes",
            "-Werror=old-style-definition",
            "-Werror=missing-prototypes",
            "-Wno-missing-braces",
        };

        lib.defineCMacroRaw("_REENTRANT");
        lib.defineCMacroRaw("_POSIX_C_SOURCE=200809L");

        lib.defineCMacroRaw("SOUNDIO_VERSION_MAJOR=2");
        lib.defineCMacroRaw("SOUNDIO_VERSION_MINOR=0");
        lib.defineCMacroRaw("SOUNDIO_VERSION_PATCH=0");
        lib.defineCMacroRaw("SOUNDIO_VERSION_STRING=\"2.0.0\"");

        var sources = [_][]const u8{
            root ++ "/src/soundio.c",
            root ++ "/src/util.c",
            root ++ "/src/os.c",
            root ++ "/src/dummy.c",
            root ++ "/src/channel_layout.c",
            root ++ "/src/ring_buffer.c",
        };

        lib.addCSourceFiles(&sources, &cflags);

        if (audio_config.jack) lib.addCSourceFile(.{ .file = std.Build.LazyPath.relative(root ++ "/src/jack.c"), .flags = &cflags });
        if (audio_config.pulseaudio) lib.addCSourceFile(.{ .file = std.Build.LazyPath.relative(root ++ "/src/pulseaudio.c"), .flags = &cflags });
        if (audio_config.alsa) lib.addCSourceFile(.{ .file = std.Build.LazyPath.relative(root ++ "/src/alsa.c"), .flags = &cflags });
        if (audio_config.coreaudio) lib.addCSourceFile(.{ .file = std.Build.LazyPath.relative(root ++ "/src/coreaudio.c"), .flags = &cflags });
        if (audio_config.wasapi) lib.addCSourceFile(.{ .file = std.Build.LazyPath.relative(root ++ "/src/wasapi.c"), .flags = &cflags });

        if (audio_config.jack) lib.defineCMacroRaw("SOUNDIO_HAVE_JACK");
        if (audio_config.pulseaudio) lib.defineCMacroRaw("SOUNDIO_HAVE_PULSEAUDIO");
        if (audio_config.alsa) lib.defineCMacroRaw("SOUNDIO_HAVE_ALSA");
        if (audio_config.coreaudio) lib.defineCMacroRaw("SOUNDIO_HAVE_COREAUDIO");
        if (audio_config.wasapi) lib.defineCMacroRaw("SOUNDIO_HAVE_WASAPI");

        if (audio_config.jack) lib.linkSystemLibrary("jack");

        if (audio_config.pulseaudio) lib.linkSystemLibrary("libpulse");

        if (audio_config.alsa) lib.linkSystemLibrary("alsa");

        if (audio_config.coreaudio) @panic("Audio for MacOS not implemented. Please find the correct libraries and stuff.");

        // if (audio_config.wasapi) lib.linkSystemLibrary("");

        lib.linkLibC();
        lib.linkSystemLibrary("m");

        lib.addIncludePath(std.Build.LazyPath.relative(root));
        lib.addIncludePath(std.Build.LazyPath.relative("src/soundio"));

        break :blk lib;
    };

    {
        const client = b.addExecutable(.{ .name = "showdown", .root_source_file = std.Build.LazyPath.relative("src/client/main.zig"), .target = target, .optimize = mode });

        addClientPackages(b, client, target, render_backend, gen_vk, asset_gen_step.package);

        // client.addBuildOption(State, "initial_state", initial_state);
        // client.addBuildOption(bool, "enable_frame_counter", enable_frame_counter);
        // client.addBuildOption(u16, "default_port", default_port);
        // client.addBuildOption(RenderBackend, "render_backend", render_backend);

        client.linkLibrary(libsoundio);

        // Needed for libsoundio:
        client.linkLibC();
        client.linkSystemLibrary("m");

        if (audio_config.jack) {
            client.linkSystemLibrary("jack");
        }
        if (audio_config.pulseaudio) {
            client.linkSystemLibrary("libpulse");
        }
        if (audio_config.alsa) {
            client.linkSystemLibrary("alsa");
        }
        if (audio_config.coreaudio) {
            @panic("Audio for MacOS not implemented. Please find the correct libraries and stuff.");
        }
        if (audio_config.wasapi) {
            // this is required for soundio
            client.linkSystemLibrary("uuid");
            client.linkSystemLibrary("ole32");
        }

        const run_client_cmd = b.addRunArtifact(client);
        run_client_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_client_cmd.addArgs(args);
        }

        const run_client_step = b.step("run", "Run the app");
        run_client_step.dependOn(&run_client_cmd.step);
    }

    {
        const server = b.addExecutable("showdown-server", "src/server/main.zig");
        server.addPackage(pkgs.network);
        server.setTarget(target);
        server.setBuildMode(mode);
        server.addBuildOption(u16, "default_port", default_port);
        server.install();

        const run_server_cmd = server.run();
        run_server_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_server_cmd.addArgs(args);
        }

        const run_server_step = b.step("run-server", "Run the app");
        run_server_step.dependOn(&run_server_cmd.step);
    }

    {
        const test_client = b.addTest("src/client/main.zig");
        addClientPackages(test_client, target, render_backend, gen_vk, asset_gen_step.package);

        test_client.addBuildOption(State, "initial_state", initial_state);
        test_client.addBuildOption(bool, "enable_frame_counter", enable_frame_counter);
        test_client.addBuildOption(u16, "default_port", default_port);
        test_client.addBuildOption(RenderBackend, "render_backend", render_backend);

        test_client.setTarget(target);
        test_client.setBuildMode(mode);

        if (mode != .Debug) {
            // TODO: Workaround for
            test_client.linkLibC();
            test_client.linkSystemLibrary("m");
        }

        const test_server = b.addTest("src/server/main.zig");
        test_server.setTarget(target);
        test_server.setBuildMode(mode);

        test_step.dependOn(&test_client.step);
        test_step.dependOn(&test_server.step);
    }

    // collision development stuff
    {
        const exe = b.addExecutable("collision", "src/development/collision.zig");
        exe.setTarget(target);
        exe.setBuildMode(mode);
        exe.addPackage(pkgs.zlm);

        const exe_step = b.step("collision", "Compiles the collider dev environment.");
        exe_step.dependOn(&exe.step);

        const run = exe.run();

        const run_step = b.step("run-collision", "Runs the collider dev environment.");
        run_step.dependOn(&run.step);

        const tst = b.addTest("src/development/collision.zig");
        tst.addPackage(pkgs.zlm);

        test_step.dependOn(&tst.step);
    }
}
