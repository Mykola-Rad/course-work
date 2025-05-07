using IMS.Models;
using Microsoft.AspNetCore.Mvc.Rendering;
using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.Linq;

namespace IMS.ViewModels
{
    public class InvoiceViewModel : IValidatableObject
    {
        public int InvoiceId { get; set; }

        [Required(ErrorMessage = "Please enter the date.")]
        [DataType(DataType.Date)]
        [Display(Name = "Document Date")]
        public DateOnly Date { get; set; } = DateOnly.FromDateTime(DateTime.Today);

        [Required(ErrorMessage = "Please select the invoice type.")]
        [Display(Name = "Invoice Type")]
        public InvoiceType Type { get; set; }

        [Display(Name = "Status")]
        public InvoiceStatus Status { get; set; } = InvoiceStatus.draft;

        [Display(Name = "Counterparty")]
        public string? CounterpartyName { get; set; }

        [Display(Name = "Sender Storage")]
        public string? SenderStorageName { get; set; }

        [Display(Name = "Receiver Storage")]
        public string? ReceiverStorageName { get; set; }

        [Display(Name = "Sender Keeper")]
        public string? SenderKeeperPhone { get; set; }

        [Display(Name = "Receiver Keeper")]
        public string? ReceiverKeeperPhone { get; set; }

        public List<InvoiceListEntryViewModel> ListEntries { get; set; } = new List<InvoiceListEntryViewModel>();

        public SelectList? AvailableTypes { get; set; }
        public SelectList? AvailableCounterparties { get; set; }
        public SelectList? AvailableStorages { get; set; }
        public SelectList? AvailableKeepers { get; set; }
        public SelectList? AvailableProducts { get; set; }

        public IEnumerable<ValidationResult> Validate(ValidationContext validationContext)
        {
            bool needsCounterparty = (Type == InvoiceType.supply || Type == InvoiceType.release);
            bool needsSenderStorage = (Type == InvoiceType.release || Type == InvoiceType.transfer);
            bool needsReceiverStorage = (Type == InvoiceType.supply || Type == InvoiceType.transfer);
            bool needsSenderKeeper = (Type == InvoiceType.release || Type == InvoiceType.transfer);
            bool needsReceiverKeeper = (Type == InvoiceType.supply || Type == InvoiceType.transfer);

            if (needsCounterparty && string.IsNullOrEmpty(CounterpartyName))
            {
                yield return new ValidationResult("Counterparty is required for this invoice type.", new[] { nameof(CounterpartyName) });
            }
            if (needsSenderStorage && string.IsNullOrEmpty(SenderStorageName))
            {
                yield return new ValidationResult("Sender Storage is required for this invoice type.", new[] { nameof(SenderStorageName) });
            }
            if (needsReceiverStorage && string.IsNullOrEmpty(ReceiverStorageName))
            {
                yield return new ValidationResult("Receiver Storage is required for this invoice type.", new[] { nameof(ReceiverStorageName) });
            }
            if (Type == InvoiceType.transfer && SenderStorageName == ReceiverStorageName && !string.IsNullOrEmpty(SenderStorageName))
            {
                yield return new ValidationResult("Sender Storage and Receiver Storage cannot be the same for a transfer.", new[] { nameof(ReceiverStorageName) });
            }

            if (needsSenderKeeper && string.IsNullOrEmpty(SenderKeeperPhone))
            {
                yield return new ValidationResult("Sender Keeper is required for this invoice type.", new[] { nameof(SenderKeeperPhone) });
            }
            if (needsReceiverKeeper && string.IsNullOrEmpty(ReceiverKeeperPhone))
            {
                yield return new ValidationResult("Receiver Keeper is required for this invoice type.", new[] { nameof(ReceiverKeeperPhone) });
            }

            if (ListEntries == null || !ListEntries.Any(le => !le.IsMarkedForDeletion))
            {
                yield return new ValidationResult("The invoice must contain at least one product item.", new[] { nameof(ListEntries) });
            }
            else
            {
                if (Type == InvoiceType.supply || Type == InvoiceType.release)
                {
                    foreach (var entry in ListEntries.Where(le => !le.IsMarkedForDeletion))
                    {
                        if (entry.Price <= 0)
                        {
                            yield return new ValidationResult($"Price for product '{entry.ProductName}' must be greater than zero.", new[] { nameof(ListEntries) });
                        }
                    }
                }
            }
        }
    }
}