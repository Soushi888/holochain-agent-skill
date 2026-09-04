use hdk::prelude::*;
use holochain::sweettest::{SweetConductor, SweetZome};
use <ZOME_NAME>_integrity::*;

pub async fn sample_post(conductor: &SweetConductor, zome: &SweetZome) -> <EntryType> {
    <EntryType> {
        title: Default::default(),
        content: Default::default(),
    }
}

pub async fn create_post(conductor: &SweetConductor, zome: &SweetZome) -> Record {
    conductor
        .call(&zome, "create_post", sample_post(conductor, zome).await)
        .await
}
