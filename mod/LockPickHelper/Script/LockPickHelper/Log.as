// The mod's log: a text file in the game's Saved folder (the release game writes no log of its own). A new file on
// every Open; the lines wait in memory and the whole file is written again on Flush (reading the file back on every
// line, as the probe did, is slow).

namespace LPH
{
	// Real time in milliseconds (works in the main menu too). In this build FDateTime ticks gave 0 and
	// System::GetPlatformTime_Seconds does not compile; Gameplay::GetAccurateRealTime does the job.
	int64 NowMs()
	{
		int Seconds = 0;
		float Partial = 0.0;
		Gameplay::GetAccurateRealTime(Seconds, Partial);
		return int64(Seconds) * 1000 + int(Partial * 1000.0);
	}

	// Line() writes the file itself no more often than this.
	const int LogFlushMs = 250;
}

class ULPH_Log : UObject
{
	// Debug() lines go to the file only when this is on.
	bool bDebug = false;

	FString Path;
	FString Buffer;
	int64 OpenedMs = 0;
	int64 FlushedMs = 0;
	bool bWaiting = false; // lines in Buffer that are not in the file yet

	// Starts a new log file Saved/<FileName> (an old one with that name is replaced).
	void Open(FString FileName)
	{
		Path = FPaths::ProjectSavedDir() + FileName;
		Buffer = "";
		OpenedMs = LPH::NowMs();
		Flush();
	}

	// One line, stamped with the milliseconds since Open. The file is written at most once per LPH::LogFlushMs here;
	// whoever ends a session calls Flush so that the last lines are not left in memory.
	void Line(FString Text)
	{
		if (Path.IsEmpty())
			return;
		int64 Now = LPH::NowMs();
		Buffer += f"[{Now - OpenedMs}] {Text}\n";
		bWaiting = true;
		if (Now - FlushedMs >= LPH::LogFlushMs)
			Flush();
	}

	// Writes the file when lines wait and LPH::LogFlushMs has passed since the last write: the glue calls it every frame,
	// so that a line reaches the file soon even when no other line follows it (a crash loses at most that much).
	void FlushIfDue()
	{
		if (bWaiting && LPH::NowMs() - FlushedMs >= LPH::LogFlushMs)
			Flush();
	}

	// A line for the report-a-bug log, only with bDebug.
	void Debug(FString Text)
	{
		if (bDebug)
			Line(Text);
	}

	// Writes the file now, as UTF-8 without a byte order mark (the default wrote UTF-16 as soon as a line had Cyrillic).
	void Flush()
	{
		if (Path.IsEmpty())
			return;
		FlushedMs = LPH::NowMs();
		bWaiting = false;
		FFileHelper::SaveStringToFile(Buffer, Path, FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM);
	}
}
