// LockDb.as (the database, the removal of connections, the lookup without case) and LockGraphs.as (the data generated
// from the Modkit sources: tools/gen_lockgraphs.py).

ULPH_LockDb LPHTests_MakeLockDb(UObject Outer)
{
	return Cast<ULPH_LockDb>(NewObject(Outer, ULPH_LockDb::StaticClass()));
}

void LPHTests_LockDb(ULPH_TestRun T)
{
	T.Begin("LockDb");

	// The generated data.
	ULPH_LockDb Db = LPHTests_MakeLockDb(T);
	LPH_RegisterLockGraphs(Db);
	T.EqualInt(Db.Num(), 416, "the database holds the 416 locks of the Modkit sources");
	T.EqualStr(LPH::LocksBuild, "Build102_CL175960", "LocksBuild");
	T.EqualStr(LPH::LocksSource, "G1R-Modkit 619c2e6", "LocksSource");

	// OC_Chest_Mud_Lock: 5 plates and six connections; the name is found without case.
	FLPH_LockGraph Graph;
	int Removed = -1;
	T.True(Db.Find(n"oc_chest_mud_lock", 0, Graph, Removed), "Find(oc_chest_mud_lock) finds OC_Chest_Mud_Lock");
	T.EqualInt(Graph.Plates, 5, "Mud: plates");
	T.EqualInt(Removed, 0, "Mud: nothing removed");
	T.EqualInt(Graph.Src.Num(), 6, "Mud: connections (Src)");
	T.EqualInt(Graph.Dst.Num(), 6, "Mud: connections (Dst)");
	T.EqualInt(Graph.Dir.Num(), 6, "Mud: connections (Dir)");
	T.EqualInt(Graph.Src[0], 4, "Mud: first connection, Src");
	T.EqualInt(Graph.Dst[0], 3, "Mud: first connection, Dst");
	T.EqualInt(Graph.Dir[0], -1, "Mud: first connection, Dir");
	T.EqualInt(Graph.Src[5], 1, "Mud: last connection, Src");
	T.EqualInt(Graph.Dst[5], 3, "Mud: last connection, Dst");
	T.EqualInt(Graph.Dir[5], -1, "Mud: last connection, Dir");
	T.EqualInt(Graph.Dir[3], 1, "Mud: a connection with the plate (0 -> 1)");

	// A name made at run time (the game hands the lock's name over as an FName from a string).
	T.True(Db.Find(FName("OC_CHEST_mud_LOCK"), 0, Graph, Removed), "Find with a name made from a string");
	T.EqualInt(Graph.Plates, 5, "Mud by a string name: plates");

	// Removal of the first connections.
	T.True(Db.Find(n"OC_Chest_Mud_Lock", 1, Graph, Removed), "Find with 1 removed");
	T.EqualInt(Removed, 1, "1 removed: OutRemoved");
	T.EqualInt(Graph.Plates, 5, "1 removed: the plates stay");
	T.EqualInt(Graph.Src.Num(), 5, "1 removed: one connection less");
	T.EqualInt(Graph.Src[0], 0, "1 removed: the first one is gone (Src)");
	T.EqualInt(Graph.Dst[0], 4, "1 removed: the first one is gone (Dst)");
	T.EqualInt(Graph.Dir[0], -1, "1 removed: the first one is gone (Dir)");
	T.EqualInt(Graph.Dst.Num(), 5, "1 removed: Dst");
	T.EqualInt(Graph.Dir.Num(), 5, "1 removed: Dir");

	T.True(Db.Find(n"OC_Chest_Mud_Lock", 2, Graph, Removed), "Find with 2 removed");
	T.EqualInt(Removed, 2, "2 removed: OutRemoved");
	T.EqualInt(Graph.Src.Num(), 4, "2 removed: four connections");
	T.EqualInt(Graph.Src[0], 0, "2 removed: Src of the first");
	T.EqualInt(Graph.Dst[0], 2, "2 removed: Dst of the first");

	// More than there are: all removed, and OutRemoved says how many there were.
	T.True(Db.Find(n"OC_Chest_Mud_Lock", 99, Graph, Removed), "Find with too many removed");
	T.EqualInt(Removed, 6, "99 removed: OutRemoved is the number of connections");
	T.EqualInt(Graph.Src.Num(), 0, "99 removed: no connections");
	T.EqualInt(Graph.Plates, 5, "99 removed: the plates stay");

	T.True(Db.Find(n"OC_Chest_Mud_Lock", 6, Graph, Removed), "Find with exactly all removed");
	T.EqualInt(Removed, 6, "6 removed: OutRemoved");
	T.EqualInt(Graph.Dir.Num(), 0, "6 removed: no connections");

	// A negative number is 0.
	T.True(Db.Find(n"OC_Chest_Mud_Lock", -3, Graph, Removed), "Find with a negative number removed");
	T.EqualInt(Removed, 0, "-3 removed: OutRemoved is 0");
	T.EqualInt(Graph.Src.Num(), 6, "-3 removed: nothing removed");

	// The same variable used again after a longer graph: the result does not keep the old connections.
	T.True(Db.Find(n"OC_Chest_Digger526_Lock", 0, Graph, Removed), "Find OC_Chest_Digger526_Lock");
	T.EqualInt(Graph.Plates, 5, "Digger526: plates");
	T.EqualInt(Graph.Src.Num(), 5, "Digger526: connections");
	T.EqualInt(Graph.Src[0], 4, "Digger526: first connection, Src");
	T.EqualInt(Graph.Dst[0], 1, "Digger526: first connection, Dst");
	T.EqualInt(Graph.Src[4], 2, "Digger526: last connection, Src");
	T.EqualInt(Graph.Dst[4], 1, "Digger526: last connection, Dst");
	T.EqualInt(Graph.Dir[4], 1, "Digger526: last connection, Dir");

	// The lock the game registers under the second m_UniqueName of its class (the first one is not a lock's name).
	T.True(Db.Find(n"Test_Lock_85_07", 0, Graph, Removed), "Find Test_Lock_85_07");
	T.EqualInt(Graph.Plates, 6, "Test_Lock_85_07: plates");
	T.EqualInt(Graph.Src.Num(), 10, "Test_Lock_85_07: connections");

	// A lock that is not in the database.
	T.True(!Db.Find(n"No_Such_Lock", 0, Graph, Removed), "Find of an unknown name is false");
	T.EqualInt(Removed, 0, "unknown name: OutRemoved is 0");
	T.EqualInt(Graph.Plates, 0, "unknown name: the graph is empty (plates)");
	T.EqualInt(Graph.Src.Num(), 0, "unknown name: the graph is empty (connections)");
	T.True(!Db.Find(NAME_None, 3, Graph, Removed), "Find of NAME_None is false");

	// The database built by hand: AddEdge goes to the last AddLock, a name added again replaces the lock.
	ULPH_LockDb Small = LPHTests_MakeLockDb(T);
	T.EqualInt(Small.Num(), 0, "an empty database has no locks");
	T.True(!Small.Find(n"A", 0, Graph, Removed), "an empty database finds nothing");
	Small.AddEdge(0, 1, 1);
	T.EqualInt(Small.Num(), 0, "AddEdge before the first AddLock does nothing");
	Small.AddLock(n"Lock_A", 3);
	Small.AddEdge(0, 1, 1);
	Small.AddLock(n"Lock_B", 2);
	Small.AddEdge(1, 0, -1);
	Small.AddEdge(0, 1, -1);
	T.EqualInt(Small.Num(), 2, "two locks");
	T.True(Small.Find(n"lock_a", 0, Graph, Removed), "Lock_A is found");
	T.EqualInt(Graph.Plates, 3, "Lock_A: plates");
	T.EqualInt(Graph.Src.Num(), 1, "Lock_A: one connection");
	T.True(Small.Find(n"LOCK_B", 0, Graph, Removed), "Lock_B is found");
	T.EqualInt(Graph.Plates, 2, "Lock_B: plates");
	T.EqualInt(Graph.Src.Num(), 2, "Lock_B: two connections");
	T.EqualInt(Graph.Dir[1], -1, "Lock_B: the second connection");
	Small.AddLock(n"LOCK_a", 4);
	Small.AddEdge(2, 3, 1);
	T.EqualInt(Small.Num(), 2, "a name added again (other case) replaces the lock");
	T.True(Small.Find(n"Lock_A", 0, Graph, Removed), "Lock_A after the replacement");
	T.EqualInt(Graph.Plates, 4, "Lock_A replaced: plates");
	T.EqualInt(Graph.Src.Num(), 1, "Lock_A replaced: only the new connection");
	T.EqualInt(Graph.Src[0], 2, "Lock_A replaced: the new connection");

	// The removal count from the lockpicking skill: round half up, 0 below 1/2 and for a negative skill.
	T.EqualInt(LPH::ConnectionsRemoved(1.4), 1, "ConnectionsRemoved(1.4)");
	T.EqualInt(LPH::ConnectionsRemoved(1.5), 2, "ConnectionsRemoved(1.5)");
	T.EqualInt(LPH::ConnectionsRemoved(-1.0), 0, "ConnectionsRemoved(-1)");
	T.EqualInt(LPH::ConnectionsRemoved(0.0), 0, "ConnectionsRemoved(0)");
	T.EqualInt(LPH::ConnectionsRemoved(0.49), 0, "ConnectionsRemoved(0.49)");
	T.EqualInt(LPH::ConnectionsRemoved(0.5), 1, "ConnectionsRemoved(0.5)");
	T.EqualInt(LPH::ConnectionsRemoved(2.5), 3, "ConnectionsRemoved(2.5)");
	T.EqualInt(LPH::ConnectionsRemoved(3.0), 3, "ConnectionsRemoved(3)");
	T.EqualInt(LPH::ConnectionsRemoved(1000000.0), 1000, "ConnectionsRemoved of a huge skill stays in the int range");
}
