using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;

namespace IMS.Models;

public partial class Counterparty
{
    [Required(ErrorMessage = "Номер телефону є обов'язковим.")]
    [StringLength(13, MinimumLength = 10, ErrorMessage = "Довжина номера телефону має бути від 10 до 13 символів.")]
    [RegularExpression(@"^\+\d+$", ErrorMessage = "Номер телефону має починатися зі знаку '+' і містити тільки цифри.")]
    [Display(Name = "Номер телефону")]
    public string PhoneNumber { get; set; } = null!;

    [Key]
    [Required(ErrorMessage = "Назва контрагента є обов'язковою.")]
    [StringLength(100, MinimumLength = 3, ErrorMessage = "Назва контрагента має бути від 3 до 100 символів.")]
    [Display(Name = "Назва контрагента")]
    public string Name { get; set; } = null!;

    [EmailAddress(ErrorMessage = "Неправильний формат Email.")]
    [StringLength(255)]
    [Display(Name = "Email")]
    public string? Email { get; set; }

    public virtual ICollection<Invoice> Invoices { get; set; } = new List<Invoice>();

    public virtual ICollection<CounterpartyRole> Roles { get; set; } = new List<CounterpartyRole>();
}
