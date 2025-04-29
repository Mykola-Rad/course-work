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

        public static List<TEntity> GenerateWithUniqueName<TEntity>(
        int count,                         
        Faker<TEntity> faker,              
        Func<TEntity, string> getName,
        Action<TEntity, string> setName)   
        where TEntity : class              
        {
            var generatedEntities = new List<TEntity>(count);
            var uniqueNames = new HashSet<string>();

            while (generatedEntities.Count < count)
            {
                var entity = faker.Generate();

                string uniqueName = getName(entity);

                if (!uniqueNames.Add(uniqueName))
                {
                    int index = 1;
                    do
                    {
                        index++;
                        uniqueName = $"{uniqueNames} {index}";
                    } while (!uniqueNames.Add(uniqueName));

                    setName(entity, uniqueName);
                }
                generatedEntities.Add(entity);
            }
            return generatedEntities;
        }
    }
}
