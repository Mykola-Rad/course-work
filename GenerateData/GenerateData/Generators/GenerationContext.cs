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

        public List<string> AvailableProductNames { get; set; } = new List<string>();
        public List<int> AvailableInvoiceIds { get; set; } = new List<int>();
        public List<string> AvailableStorageNames { get; set; } = new List<string>();
        public  List<string> AvailableUsernames { get; set; } = new List<string>();
        public List<string> AvailableKeeperPhones { get; set; } = new List<string>();
        public List<string> AvailableCounterpartyNames { get; set; } = new List<string>();
        public List<string> AvailableUnitCodes { get; set; } = new List<string>();
        public List<(string storageName, string productName)> AvailableStorageProducts { get; set; } = new List<(string, string)>();
    }
}
