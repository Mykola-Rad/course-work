using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace IMS.Models;

public partial class Product
{
    [Key]
    [Required(ErrorMessage = "Product name is required.")]
    [StringLength(100, ErrorMessage = "Product name cannot exceed 100 characters.")]
    [Display(Name = "Product Name")]
    public string ProductName { get; set; } = null!;

    [Required(ErrorMessage = "Unit of measure is required.")]
    [StringLength(10)]
    [Display(Name = "Unit Code")]
    public string UnitCode { get; set; } = null!;

    [Required(ErrorMessage = "Price is required.")]
    [Range(0.01, 99999999.99, ErrorMessage = "Price must be a positive number.")]
    [Display(Name = "Last Price")]
    public decimal LastPrice { get; set; }

    public virtual ICollection<ListEntry> ListEntries { get; set; } = new List<ListEntry>();

    public virtual ICollection<StorageProduct> StorageProducts { get; set; } = new List<StorageProduct>();

    [ForeignKey("UnitCode")]
    [Display(Name = "Unit of Measure")]
    public virtual ProductUnit UnitCodeNavigation { get; set; } = null!;
}