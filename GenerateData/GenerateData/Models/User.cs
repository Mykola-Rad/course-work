using System;
using System.Collections.Generic;

namespace GenerateData.Models;

public partial class User
{
    public string Username { get; set; } = null!;

    public string PasswordHash { get; set; } = null!;

    public virtual StorageKeeper? StorageKeeper { get; set; }
}
