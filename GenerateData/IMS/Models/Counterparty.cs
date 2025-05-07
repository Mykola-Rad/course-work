using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;

namespace IMS.Models;

public partial class Counterparty
{
    [Required(ErrorMessage = "Phone number is required.")]
    [StringLength(13, MinimumLength = 10, ErrorMessage = "The phone number length must be between 10 and 13 characters.")]
    [RegularExpression(@"^\+\d+$", ErrorMessage = "The phone number must start with '+' and contain only digits.")]
    [Display(Name = "Phone Number")]
    public string PhoneNumber { get; set; } = null!;

    [Key]
    [Required(ErrorMessage = "Counterparty name is required.")]
    [StringLength(100, MinimumLength = 3, ErrorMessage = "The counterparty name must be between 3 and 100 characters.")]
    [Display(Name = "Counterparty Name")]
    public string Name { get; set; } = null!;

    [EmailAddress(ErrorMessage = "Invalid Email format.")]
    [StringLength(255)]
    [Display(Name = "Email")]
    public string? Email { get; set; }

    public virtual ICollection<Invoice> Invoices { get; set; } = new List<Invoice>();

    public virtual ICollection<CounterpartyRole> Roles { get; set; } = new List<CounterpartyRole>();
}