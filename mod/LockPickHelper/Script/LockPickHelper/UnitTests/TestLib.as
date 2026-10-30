// The tests' checks. A test is `void LPHTests_<Module>(ULPH_TestRun T)` in UnitTests/<Module>Test.as; the list of them is in
// TestRunner.as. Every check counts as passed or failed; a failure goes to the test log as
// `FAIL <case>: <what> (got <actual>, want <expected>)`.

class ULPH_TestRun : UObject
{
	UPROPERTY()
	ULPH_Log Output;

	int Passed = 0;
	int Failed = 0;
	FString CurrentCase;

	// Starts a group of checks (a module or one scenario): its name goes into every FAIL line after it.
	void Begin(FString Case)
	{
		CurrentCase = Case;
		if (Output != nullptr)
		{
			Output.Line(f"case {Case}");
			// A script error or a crash inside the case must not take the lines written so far with it.
			Output.Flush();
		}
	}

	void True(bool bValue, FString What)
	{
		if (bValue)
			Passed++;
		else
			Fail(What, "false", "true");
	}

	void EqualInt(int Actual, int Expected, FString What)
	{
		if (Actual == Expected)
			Passed++;
		else
			Fail(What, f"{Actual}", f"{Expected}");
	}

	void EqualStr(FString Actual, FString Expected, FString What)
	{
		if (Actual == Expected)
			Passed++;
		else
			Fail(What, "\"" + Actual + "\"", "\"" + Expected + "\"");
	}

	void Fail(FString What, FString Got, FString Want)
	{
		Failed++;
		if (Output != nullptr)
			Output.Line(f"FAIL {CurrentCase}: {What} (got {Got}, want {Want})");
	}
}
