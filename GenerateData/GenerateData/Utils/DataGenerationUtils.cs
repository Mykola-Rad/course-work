using Bogus;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace GenerateData.Utills
{
    public static class DataGenerationUtils
    {
        public static string GenerateValue(Func<Faker, string> generator, int maxLength, Faker faker)
        {
            if (generator == null || faker == null || maxLength <= 0)
                return string.Empty;

            string value;
            do
            {
                value = generator(faker);

                if (value == null)
                {
                    value = string.Empty; 
                    break;
                }
            } while (value.Length > maxLength);

            return value;
        }
    }
}
