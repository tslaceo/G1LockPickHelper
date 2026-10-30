// Fixture of tests/test_gen_lockgraphs.py: lock classes cut from Script/Items/GenericItems/LockPickGeneric.as of the
// G1R-Modkit (commit 619c2e6). The comments, the order of the lines and two of the classes are added on purpose, to
// exercise the parser (in the sources they come with trailing comments, hand-commented connections and so on).

/* A block comment with a class that must not be found:
class UNot_A_Lock: UGothicLockConfig
{
    default AddPiece(0, 0);
}
*/

////////////////////////////////////////////////////////////////////////
//******************OLD CAMP (a banner like the sources have)******** */
////////////////////////////////////////////////////////////////////////

UCLASS()
class UOC_Chest_Digger526_Lock: UGothicLockConfig
{
    default m_UniqueName = n"OC_Chest_Digger526_Lock";

    default AddPiece(0, -3);
    default AddPiece(1, -3);
    default AddPiece(2, -2);
    default AddPiece(3, 0);
    default AddPiece(4, -3);

    default AddConnection(4, 1, -1);
    default AddConnection(2, 4, -1);
    default AddConnection(0, 4, -1);
    default AddConnection(3, 1, 1);
    default AddConnection(2, 1, 1);
}

UCLASS()
class UOC_Chest_Mud_Lock: UGothicLockConfig // a comment after the class header
{
    default m_UniqueName = n"OC_Chest_Mud_Lock";

    default AddPiece(0, -3);
    default AddPiece(1, -1);
    default AddPiece(2, -3);
    default AddPiece(3, -3);
    default AddPiece(4, -1);

    default AddConnection(4, 3, -1);
    default AddConnection(0, 4, -1);
    default AddConnection(0, 2, -1);
    default AddConnection(0, 1, 1);
    default AddConnection(4, 2, 1);
    default AddConnection(1, 3, -1);
}

UCLASS()
class UAM_Chest_04_Lock: UGothicLockConfig  // USED
{
    // The connections come first, a connection is commented out, the pieces are in another order, the name comes last.
    default AddConnection(2, 1, -1);
    default AddConnection(4, 0, -1);
    // default AddConnection(1, 2, -1);
    default AddConnection(0, 2, -1);
    default AddConnection(4, 1, -1);   // default AddConnection(1, 3, 1);
    default AddConnection(3, 5, 1);

    default AddPiece(5, 1);
    default AddPiece(2, 3);
    default AddPiece(0, 1);
    default AddPiece(4, 1);
    default AddPiece(1, 0);
    default AddPiece(3, -1);

    default m_UniqueName = n"AM_Chest_04_Lock";
}

UCLASS()
class UFixture_Unnamed_Lock: UGothicLockConfig
{
    default AddPiece(0, 2);
    default AddPiece(1, -2);
    default AddConnection(1, 0, 1);
}

UCLASS()
class Fixture_Plain_Lock: UGothicLockConfig
{
    default AddPiece(0, 0);
}

UCLASS()
class UOC_Chest_Mud_Chest: UIoChestDefault
{
    default m_Lock = n"OC_Chest_Mud_Lock";
    default AddPiece(0, 3);
}

UCLASS()
class UOC_Mages_Room_01_Lock: UGothicLockConfig
{
    default m_UniqueName = n"OC_Mages_Room_01_Lock";
    default m_UniqueName = n"Test_Lock_85_07";
    default AddPiece(0, -3);
    default AddPiece(1, 0);
    default AddPiece(2, 0);
    default AddPiece(3, -1);
    default AddPiece(4, 3);
    default AddPiece(5, -3);

    default AddConnection(0, 3, -1);
    default AddConnection(1, 2, -1);
    default AddConnection(3, 2, 1);
    default AddConnection(0, 2, 1);
    default AddConnection(1, 5, 1);
    default AddConnection(0, 4, 1);
    default AddConnection(0, 1, 1);
    default AddConnection(1, 0, -1);
    default AddConnection(3, 0, -1);
    default AddConnection(3, 4, -1);
}
