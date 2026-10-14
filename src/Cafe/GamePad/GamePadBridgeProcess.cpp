#include "Cafe/GamePad/GamePadBridgeProcess.h"
#include "config/ActiveSettings.h"

#if BOOST_OS_LINUX
#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>

extern char** environ;
#endif

namespace GamePadBridgeProcess
{
	namespace
	{
		constexpr sint64 kStartupNs = 15'000'000'000; // a bridge that hasn't answered by now counts as broken
		// Written by the GamePad network service (scripts/pad-net.sh): connected / disconnected / down
		constexpr const char* kPadStatusFile = "/run/cemu-gamepad/pad";

		bool IsExecutable(const fs::path& p)
		{
#if BOOST_OS_LINUX
			std::error_code ec;
			return fs::is_regular_file(p, ec) && access(p.c_str(), X_OK) == 0;
#else
			return false;
#endif
		}

		sint64 MonotonicNs()
		{
#if BOOST_OS_LINUX
			timespec ts;
			clock_gettime(CLOCK_MONOTONIC, &ts);
			return sint64(ts.tv_sec) * 1'000'000'000 + ts.tv_nsec;
#else
			return 0;
#endif
		}

		// The pad network is up (the bridge exits at once without it)
		bool PadNetworkUp()
		{
			std::ifstream f(kPadStatusFile);
			std::string state;
			return f && std::getline(f, state) && (state == "connected" || state == "disconnected");
		}

		fs::path BridgeExecutable()
		{
			if (const char* env = getenv("CEMU_GAMEPAD_BRIDGE"); env && *env && IsExecutable(env))
				return env;
			const fs::path root = BundleRoot();
			if (root.empty())
				return {};
			for (const fs::path& p : {root / "bin/cemu-gamepad-bridge", root / "build/bridge/cemu-gamepad-bridge"})
				if (IsExecutable(p))
					return p;
			return {};
		}

		// The running executable. Not ActiveSettings::GetExecutablePath(): from an AppImage, that's the AppImage file
		// (CemuApp::DeterminePaths), and the bridge is inside it, next to the real executable.
		fs::path RunningExecutable()
		{
			std::error_code ec;
			fs::path exe = fs::read_symlink("/proc/self/exe", ec);
			return ec ? ActiveSettings::GetExecutablePath() : exe;
		}

#if BOOST_OS_LINUX
		pid_t child = -1;
		sint64 childStartedNs = 0;
		bool logTruncated = false;
#endif
	}

	fs::path BundleRoot()
	{
		const fs::path exeDir = RunningExecutable().parent_path();
		for (const fs::path& p : {exeDir / "../lib/cemu-gamepad", exeDir / "../gamepad-bridge"})
		{
			std::error_code ec;
			if (fs::is_regular_file(p / "scripts/gamepad-setup.sh", ec))
				return fs::weakly_canonical(p, ec);
		}
		return {};
	}

	bool InAppImage()
	{
		// $APPDIR alone isn't enough: Cemu built from source, started by another AppImage (ES-DE is one), inherits it
		const char* appDir = getenv("APPDIR");
		const char* appImage = getenv("APPIMAGE");
		if (!appDir || !*appDir || !appImage || !*appImage)
			return false;
		std::error_code ec;
		const fs::path dir = fs::weakly_canonical(appDir, ec);
		const fs::path exe = fs::weakly_canonical(RunningExecutable(), ec);
		const auto rel = exe.lexically_relative(dir);
		return !rel.empty() && *rel.begin() != ".." && fs::is_regular_file(appImage, ec);
	}

	fs::path AppImageFile()
	{
		return InAppImage() ? fs::path(getenv("APPIMAGE")) : fs::path();
	}

	bool StartIfNeeded()
	{
#if BOOST_OS_LINUX
		if (child > 0)
		{
			int status = 0;
			const pid_t r = waitpid(child, &status, WNOHANG);
			if (r == 0)
				return MonotonicNs() - childStartedNs < kStartupNs; // still running
			if (r == child)
				cemuLog_log(LogType::Force, "GamePad Bridge: the bridge exited ({} {}), see gamepad-bridge.log",
							WIFEXITED(status) ? "code" : "signal", WIFEXITED(status) ? WEXITSTATUS(status) : WTERMSIG(status));
			child = -1;
		}
		if (!PadNetworkUp())
			return false;
		const fs::path exe = BridgeExecutable();
		if (exe.empty())
			return false;

		const fs::path logPath = ActiveSettings::GetUserDataPath("gamepad-bridge.log");
		posix_spawn_file_actions_t actions;
		posix_spawn_file_actions_init(&actions);
		posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
		// a fresh log per Cemu session; restarts within it append
		posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, logPath.c_str(),
										 O_WRONLY | O_CREAT | (logTruncated ? O_APPEND : O_TRUNC), 0644);
		posix_spawn_file_actions_adddup2(&actions, STDOUT_FILENO, STDERR_FILENO);
		// No DSU server: Cemu takes the GamePad's input over the bridge connection, and port 26760 is often
		// taken by another DSU server (SteamDeckGyroDSU on SteamOS).
		const std::string exeStr = exe.string();
		const char* argv[] = {exeStr.c_str(), "--pad", "real", "--stats-interval", "10", "--dsu-port", "0",
							  "--exit-with-parent", nullptr};
		pid_t pid = -1;
		const int err = posix_spawn(&pid, exeStr.c_str(), &actions, nullptr, const_cast<char**>(argv), environ);
		posix_spawn_file_actions_destroy(&actions);
		if (err != 0)
		{
			cemuLog_log(LogType::Force, "GamePad Bridge: couldn't start {}: {}", exeStr, strerror(err));
			return false;
		}
		logTruncated = true;
		child = pid;
		childStartedNs = MonotonicNs();
		cemuLog_log(LogType::Force, "GamePad Bridge: started {} (pid {}), log: {}", exeStr, pid, _pathToUtf8(logPath));
		return true;
#else
		return false;
#endif
	}
}
