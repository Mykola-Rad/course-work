using Bogus;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace GenerateData.Generators
{
    public class GenerationContext
    {
        public Random Random { get; } = new Random();
        public Faker Faker { get; } = new Faker();

        public List<string> GeneratedProductNames { get; set; } = new List<string>();
        public List<int> GeneratedInvoiceIds { get; set; } = new List<int>();
        public List<string> GeneratedStorageNames { get; set; } = new List<string>();
        public List<string> GeneratedUsernames { get; set; } = new List<string>();
        public List<string> GeneratedKeeperPhones { get; set; } = new List<string>();
        public List<string> GeneratedCounterpartyNames { get; set; } = new List<string>();
        public List<string> AvailableUnitCodes { get; set; } = new List<string>(); 
    }
}
