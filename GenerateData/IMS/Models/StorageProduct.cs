using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;

namespace IMS.Models;

public partial class StorageProduct
{
    public string StorageName { get; set; } = null!;

    public string ProductName { get; set; } = null!;

    [Range(0.01, 1000000, ErrorMessage = "Count must be a non-negative number.")]
    public decimal Count { get; set; }

    [Range(0.01, 1000000, ErrorMessage = "Minimal Count must be a non-negative number.")]
    public decimal MinimalCount { get; set; }

    public virtual Product ProductNameNavigation { get; set; } = null!;

    public virtual Storage StorageNameNavigation { get; set; } = null!;
}