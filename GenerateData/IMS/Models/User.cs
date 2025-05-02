using System;
using System.Collections.Generic;

namespace IMS.Models;

public partial class User
{
    public int UserId { get; set; }

    public string Username { get; set; } = null!;

    public string PasswordHash { get; set; } = null!;

    public string Role { get; set; }

    public virtual StorageKeeper? StorageKeeper { get; set; }
}
