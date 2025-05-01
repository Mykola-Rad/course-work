namespace GenerateData.Models;

public partial class User
{
    public string Username { get; set; } = null!;

    public string PasswordHash { get; set; } = null!;

    public string Role { get; set; }

    public virtual StorageKeeper? StorageKeeper { get; set; }
}
