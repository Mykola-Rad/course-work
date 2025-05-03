using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace IMS.Models;

public partial class Product
{
    [Key] 
    [Required(ErrorMessage = "Назва товару є обов'язковою.")]
    [StringLength(100, ErrorMessage = "Назва товару не може перевищувати 100 символів.")]
    [Display(Name = "Назва товару")]
    public string ProductName { get; set; } = null!;

    [Required(ErrorMessage = "Одиниця виміру є обов'язковою.")]
    [StringLength(10)]
    [Display(Name = "Код од. виміру")]
    public string UnitCode { get; set; } = null!;

    [Required(ErrorMessage = "Ціна є обов'язковою.")]
    [Range(0.01, 99999999.99, ErrorMessage = "Ціна повинна бути позитивним числом.")] 
    [Display(Name = "Остання ціна")]
    public decimal LastPrice { get; set; }

    public virtual ICollection<ListEntry> ListEntries { get; set; } = new List<ListEntry>();

    public virtual ICollection<StorageProduct> StorageProducts { get; set; } = new List<StorageProduct>();

    [ForeignKey("UnitCode")] 
    [Display(Name = "Одиниця виміру")]
    public virtual ProductUnit UnitCodeNavigation { get; set; } = null!;
}
