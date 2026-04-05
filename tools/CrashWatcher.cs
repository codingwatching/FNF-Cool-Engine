// =============================================================================
//  CrashWatcher.cs — Cool Engine External Crash Reporter
// =============================================================================
//
//  PURPOSE
//  -------
//  This is a completely separate process from the game.
//  It is spawned by CrashHandler.init() at game startup, given the game's PID,
//  and silently waits in the background.
//
//  If the game exits with a non-zero exit code (any crash: null object
//  reference, hscript error, mod error, native access violation, etc.),
//  this reporter reads the latest crash log written by CrashHandler.hx and
//  shows a proper dialog window — guaranteed, because it runs in its own
//  process with a clean heap and no dependency on game state.
//
//  If the game exits normally (code 0), this process exits silently.
//
//  COMMAND-LINE ARGUMENTS
//  ----------------------
//    CrashWatcher.exe --pid <game_pid> --logdir <crash_folder> [--url <report_url>]
//
//  COMPILATION
//  -----------
//  Run build_watcher.bat (uses the .NET Framework csc.exe bundled with Windows).
//  Output: CrashWatcher.exe  — place it next to the game executable.
//
// =============================================================================

using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

[assembly: System.Reflection.AssemblyTitle("Cool Engine Crash Reporter")]
[assembly: System.Reflection.AssemblyVersion("1.0.0.0")]

namespace CoolEngineCrashWatcher
{
    // =========================================================================
    //  Entry point
    // =========================================================================

    // =========================================================================
    //  Win32 P/Invoke helpers
    //  Using OpenProcess + WaitForSingleObject + GetExitCodeProcess instead of
    //  Process.GetProcessById + WaitForExit because the managed API throws
    //  ArgumentException when the target process has already exited before we
    //  can attach — causing a false-positive crash dialog on every normal exit.
    // =========================================================================

    static class NativeMethods
    {
        // Access rights
        public const uint PROCESS_SYNCHRONIZE               = 0x00100000;
        public const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x00001000;

        // WaitForSingleObject return values
        public const uint WAIT_OBJECT_0 = 0x00000000;
        public const uint INFINITE      = 0xFFFFFFFF;

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr OpenProcess(
            uint dwDesiredAccess, bool bInheritHandle, int dwProcessId);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern uint WaitForSingleObject(
            IntPtr hHandle, uint dwMilliseconds);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool GetExitCodeProcess(
            IntPtr hProcess, out uint lpExitCode);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool CloseHandle(IntPtr hObject);
    }

    // =========================================================================
    //  Entry point
    // =========================================================================

    static class Program
    {
        // Sentinel value returned by WaitForProcess when we could not open a
        // handle to the game process (it had already exited before we tried).
        // We treat this as "exit code unknown" — NOT as a crash.
        const int EXIT_CODE_UNKNOWN = int.MinValue;

        /// <summary>
        /// Parses arguments, waits for the game process, and shows the crash dialog if needed.
        /// All exceptions are caught so that the watcher itself never crashes silently.
        /// </summary>
        [STAThread]
        static void Main(string[] args)
        {
            // --- Parse arguments ---
            int gamePid = -1;
            string logDir = "./crash/";
            string reportUrl = "https://github.com/The-Cool-Engine-Crew/FNF-Cool-Engine/issues";

            for (int i = 0; i < args.Length - 1; i++)
            {
                switch (args[i])
                {
                    case "--pid":
                        int.TryParse(args[i + 1], out gamePid);
                        break;
                    case "--logdir":
                        logDir = args[i + 1];
                        break;
                    case "--url":
                        reportUrl = args[i + 1];
                        break;
                }
            }

            if (gamePid <= 0)
            {
                // No valid PID — nothing to watch
                return;
            }

            // --- Wait for the game process to exit and get its exit code ---
            int exitCode = WaitForProcess(gamePid);

            // Exit code 0 → clean shutdown, definitely do nothing.
            if (exitCode == 0)
                return;

            // Give CrashHandler.hx time to finish flushing the log file before
            // we try to read it.  We wait regardless of whether exit code is
            // known or not, because the log flush races against process teardown.
            Thread.Sleep(1500);

            // --- Decide whether to show a crash dialog ---
            //
            // Three cases:
            //   a) exitCode is a known non-zero value  → crash confirmed, show dialog.
            //   b) exitCode == EXIT_CODE_UNKNOWN        → we couldn't open the process
            //      handle (it had already gone); show dialog ONLY if a recent crash
            //      log exists, otherwise assume clean exit.
            //   c) exitCode == 0                       → handled above, already returned.

            bool showDialog = false;

            if (exitCode != EXIT_CODE_UNKNOWN)
            {
                // Case (a): confirmed crash via exit code.
                showDialog = true;
            }
            else
            {
                // Case (b): exit code unknown — use crash log as the arbiter.
                // If the game crashed, CrashHandler.hx will have written a log
                // within the last 30 s.  If there is no recent log it exited cleanly
                // but was simply too fast for us to open a handle.
                showDialog = HasRecentLog(logDir, 30);
            }

            if (!showDialog)
                return;

            // --- Find and read the crash report ---
            string crashReport = ReadLatestLog(logDir, exitCode);

            // --- Show the crash dialog ---
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new CrashDialog(crashReport, logDir, reportUrl, exitCode));
        }

        // -------------------------------------------------------------------------

        /// <summary>
        /// Opens a Win32 handle to the game process, waits for it to exit, then
        /// returns its exit code.
        ///
        /// Returns <see cref="EXIT_CODE_UNKNOWN"/> (int.MinValue) when:
        ///   • the process had already exited before we could open a handle, OR
        ///   • any Win32 / .NET error prevents us from getting the exit code.
        ///
        /// Using OpenProcess + WaitForSingleObject + GetExitCodeProcess instead of
        /// the managed Process.GetProcessById API because the latter throws
        /// ArgumentException when the process is already gone, which we previously
        /// mis-interpreted as a crash (returning -1 and showing a false crash dialog
        /// on every normal game exit).
        /// </summary>
        static int WaitForProcess(int pid)
        {
            IntPtr handle = NativeMethods.OpenProcess(
                NativeMethods.PROCESS_SYNCHRONIZE | NativeMethods.PROCESS_QUERY_LIMITED_INFORMATION,
                false, pid);

            if (handle == IntPtr.Zero)
            {
                // Could not open handle: either the process is already gone or we
                // lack permissions.  In either case we don't know the exit code.
                return EXIT_CODE_UNKNOWN;
            }

            try
            {
                NativeMethods.WaitForSingleObject(handle, NativeMethods.INFINITE);

                uint code;
                if (NativeMethods.GetExitCodeProcess(handle, out code))
                    return (int)code;

                return EXIT_CODE_UNKNOWN;
            }
            catch
            {
                return EXIT_CODE_UNKNOWN;
            }
            finally
            {
                NativeMethods.CloseHandle(handle);
            }
        }

        // -------------------------------------------------------------------------

        /// <summary>
        /// Returns true if a .txt file exists in <paramref name="logDir"/> whose
        /// last-write time is within the last <paramref name="maxAgeSecs"/> seconds.
        /// Used as a secondary crash indicator when the exit code is unknown.
        /// </summary>
        static bool HasRecentLog(string logDir, double maxAgeSecs)
        {
            try
            {
                if (!Directory.Exists(logDir)) return false;
                var logs = Directory.GetFiles(logDir, "*.txt")
                                    .Select(f => new FileInfo(f))
                                    .OrderByDescending(f => f.LastWriteTime)
                                    .ToArray();
                return logs.Length > 0 &&
                       (DateTime.Now - logs[0].LastWriteTime).TotalSeconds < maxAgeSecs;
            }
            catch { return false; }
        }

        /// <summary>
        /// Reads the most recently modified .txt file from <paramref name="logDir"/>.
        /// Returns a fallback message if no log is found.
        /// </summary>
        static string ReadLatestLog(string logDir, int exitCode)
        {
            try
            {
                if (Directory.Exists(logDir))
                {
                    var logs = Directory.GetFiles(logDir, "*.txt")
                                        .Select(f => new FileInfo(f))
                                        .OrderByDescending(f => f.LastWriteTime)
                                        .ToArray();

                    // Accept log files written within the last 60 seconds.
                    if (logs.Length > 0 && (DateTime.Now - logs[0].LastWriteTime).TotalSeconds < 60)
                        return File.ReadAllText(logs[0].FullName);
                }
            }
            catch { /* Fall through to the generic message */ }

            // No log file found — show a generic message.
            // Note: exitCode may be EXIT_CODE_UNKNOWN (int.MinValue) here; display
            // a human-readable label in that case instead of an ugly hex number.
            string codeStr = (exitCode == EXIT_CODE_UNKNOWN)
                ? "unknown (process exited before watcher could attach)"
                : "0x" + ((uint)exitCode).ToString("X8") + "  (" + exitCode + ")";

            return
                "===========================================\n" +
                "       COOL ENGINE — CRASH REPORT\n" +
                "===========================================\n\n" +
                "The game terminated unexpectedly.\n\n" +
                "Exit code : " + codeStr + "\n\n" +
                "No crash log was generated.\n" +
                "This usually means the crash occurred before CrashHandler could write a log,\n" +
                "or the crash log directory is not accessible.\n\n" +
                "Common causes:\n" +
                "  • Native access violation (null pointer at C++ level)\n" +
                "  • Stack overflow with no stack space left to run the handler\n" +
                "  • Process killed externally (task manager, antivirus, etc.)\n\n" +
                "Try running the game from a terminal to see if any output appears before the crash.";
        }
    }

    // =========================================================================
    //  Crash dialog window
    // =========================================================================

    sealed class CrashDialog : Form
    {
        // Win32 import to open a folder in Explorer
        [DllImport("shell32.dll")]
        static extern IntPtr ShellExecute(
            IntPtr hwnd, string op, string file, string parameters, string dir, int show);

        // ── UI colours (dark theme) ──────────────────────────────────────────
        static readonly Color BgDark = Color.FromArgb(28, 28, 30);
        static readonly Color BgPanel = Color.FromArgb(44, 44, 46);
        static readonly Color AccentRed = Color.FromArgb(255, 59, 48);
        static readonly Color TextPrimary = Color.FromArgb(242, 242, 247);
        static readonly Color TextMuted = Color.FromArgb(174, 174, 178);
        static readonly Color BtnBg = Color.FromArgb(58, 58, 60);
        static readonly Color BtnHover = Color.FromArgb(72, 72, 74);

        // ── References ───────────────────────────────────────────────────────
        readonly string _logDir;
        readonly string _reportUrl;
        readonly string _crashText;
        RichTextBox _textBox;

        public CrashDialog(string crashText, string logDir, string reportUrl, int exitCode)
        {
            _crashText = crashText;
            _logDir = logDir;
            _reportUrl = reportUrl;

            BuildUI(exitCode);
        }

        // -------------------------------------------------------------------------

        // Returns "Cascadia Code" 8.5pt if installed, otherwise "Consolas" 9pt.
        // Avoids C# 7 pattern matching (is Font f) so it compiles under C# 5 / csc.exe.
        static Font GetMonoFont()
        {
            var f = new Font("Cascadia Code", 8.5f);
            return f.Name == "Cascadia Code" ? f : new Font("Consolas", 9f);
        }

        // -------------------------------------------------------------------------

        void BuildUI(int exitCode)
        {
            // ── Form properties ──────────────────────────────────────────────
            Text = "Cool Engine — Crash Reporter";
            Size = new Size(760, 560);
            MinimumSize = new Size(600, 400);
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = BgDark;
            ForeColor = TextPrimary;
            Font = new Font("Segoe UI", 9f);
            FormBorderStyle = FormBorderStyle.Sizable;
            Icon = SystemIcons.Error;

            // ── Header panel ─────────────────────────────────────────────────
            var header = new Panel
            {
                Dock = DockStyle.Top,
                Height = 70,
                BackColor = BgPanel,
                Padding = new Padding(16, 0, 16, 0),
            };

            var iconLabel = new Label
            {
                Text = "💥",
                Font = new Font("Segoe UI Emoji", 22f),
                ForeColor = AccentRed,
                AutoSize = true,
                Location = new Point(16, 14),
            };

            var titleLabel = new Label
            {
                Text = "The game has crashed",
                Font = new Font("Segoe UI Semibold", 14f, FontStyle.Bold),
                ForeColor = TextPrimary,
                AutoSize = true,
                Location = new Point(60, 12),
            };

            var subtitleLabel = new Label
            {
                Text = "Exit code: 0x" + exitCode.ToString("X8") + "  \u2014  A crash report has been saved.",
                Font = new Font("Segoe UI", 8.5f),
                ForeColor = TextMuted,
                AutoSize = true,
                Location = new Point(61, 40),
            };

            header.Controls.AddRange(new Control[] { iconLabel, titleLabel, subtitleLabel });

            // ── Report text area ─────────────────────────────────────────────
            var textPanel = new Panel
            {
                Dock = DockStyle.Fill,
                Padding = new Padding(12, 8, 12, 8),
                BackColor = BgDark,
            };

            _textBox = new RichTextBox
            {
                Dock = DockStyle.Fill,
                ReadOnly = true,
                Text = _crashText,
                Font = GetMonoFont(),
                BackColor = BgPanel,
                ForeColor = TextPrimary,
                BorderStyle = BorderStyle.None,
                ScrollBars = RichTextBoxScrollBars.Vertical,
                WordWrap = false,
                Padding = new Padding(8),
            };
            textPanel.Controls.Add(_textBox);

            // ── Button bar ───────────────────────────────────────────────────
            var buttonBar = new Panel
            {
                Dock = DockStyle.Bottom,
                Height = 52,
                BackColor = BgPanel,
                Padding = new Padding(12, 8, 12, 8),
            };

            var btnCopy = MakeButton("📋  Copy Report", OnCopy);
            var btnFolder = MakeButton("📁  Open Folder", OnOpenFolder);
            var btnGitHub = MakeButton("🐞  Report Bug", OnReportBug);
            var btnClose = MakeButton("✕  Close", (s, e) => Close());

            btnClose.ForeColor = AccentRed;

            // Flow layout keeps buttons tidy on resize
            var flow = new FlowLayoutPanel
            {
                Dock = DockStyle.Fill,
                FlowDirection = FlowDirection.LeftToRight,
                WrapContents = false,
            };
            flow.Controls.AddRange(new Control[] { btnCopy, btnFolder, btnGitHub });

            // Close button pinned to the right
            var rightFlow = new FlowLayoutPanel
            {
                Dock = DockStyle.Right,
                FlowDirection = FlowDirection.RightToLeft,
                AutoSize = true,
            };
            rightFlow.Controls.Add(btnClose);

            buttonBar.Controls.Add(flow);
            buttonBar.Controls.Add(rightFlow);

            // ── Assemble ─────────────────────────────────────────────────────
            Controls.Add(textPanel);
            Controls.Add(buttonBar);
            Controls.Add(header);

            // Scroll to top after layout
            Load += (s, e) => { _textBox.SelectionStart = 0; _textBox.ScrollToCaret(); };
        }

        // -------------------------------------------------------------------------
        //  Button factory

        Button MakeButton(string text, EventHandler onClick)
        {
            var btn = new Button
            {
                Text = text,
                AutoSize = true,
                MinimumSize = new Size(120, 32),
                BackColor = BtnBg,
                ForeColor = TextPrimary,
                FlatStyle = FlatStyle.Flat,
                Font = new Font("Segoe UI", 8.5f),
                Cursor = Cursors.Hand,
                Margin = new Padding(0, 0, 8, 0),
            };
            btn.FlatAppearance.BorderSize = 0;
            btn.FlatAppearance.MouseOverBackColor = BtnHover;
            btn.FlatAppearance.MouseDownBackColor = BgPanel;
            btn.Click += onClick;
            return btn;
        }

        // -------------------------------------------------------------------------
        //  Button handlers

        void OnCopy(object s, EventArgs e)
        {
            try
            {
                Clipboard.SetText(_crashText);
                var btn = (Button)s;
                string orig = btn.Text;
                btn.Text = "✔  Copied!";
                var timer = new System.Windows.Forms.Timer { Interval = 1500 };
                timer.Tick += (_, __) => { btn.Text = orig; timer.Stop(); };
                timer.Start();
            }
            catch { /* Clipboard might be locked by another process */ }
        }

        void OnOpenFolder(object s, EventArgs e)
        {
            try
            {
                string path = Path.GetFullPath(_logDir);
                if (Directory.Exists(path))
                    ShellExecute(IntPtr.Zero, "open", path, null, null, 1);
                else
                    MessageBox.Show(
                        "Crash folder not found:\n" + path,
                        "Folder not found",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Warning);
            }
            catch { }
        }

        void OnReportBug(object s, EventArgs e)
        {
            try { Process.Start(_reportUrl); }
            catch { }
        }

        // Keep dark background on resize
        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
        }
    }
}
