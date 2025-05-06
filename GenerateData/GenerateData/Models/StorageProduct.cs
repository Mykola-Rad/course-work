namespace GenerateData.Models;

public partial class StorageProduct
{
    public string StorageName { get; set; } = null!;

    public string ProductName { get; set; } = null!;

    public decimal Count { get; set; }

    public decimal MinimalCount { get; set; }

    public virtual Product ProductNameNavigation { get; set; } = null!;

    public virtual Storage StorageNameNavigation { get; set; } = null!;
}
