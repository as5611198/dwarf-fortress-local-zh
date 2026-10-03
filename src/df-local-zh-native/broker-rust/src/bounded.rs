//! FIFO limits for reconstructible in-memory caches. Persistent journals remain authoritative.
use std::{borrow::Borrow,collections::{HashMap,VecDeque},hash::Hash,ops::Deref};
pub struct BoundedMap<K,V> { rows:HashMap<K,V>, order:VecDeque<K>, capacity:usize }
impl<K:Eq+Hash+Clone,V> BoundedMap<K,V> {
  pub fn new(capacity:usize)->Self {assert!(capacity>0);Self{rows:HashMap::new(),order:VecDeque::new(),capacity}}
  pub fn insert(&mut self,key:K,value:V)->Option<V> {
    if self.rows.contains_key(&key) {return self.rows.insert(key,value)}
    if self.rows.len()>=self.capacity {
      if let Some(old)=self.order.pop_front() {self.rows.remove(&old);}
    }
    self.order.push_back(key.clone());self.rows.insert(key,value)
  }
  pub fn remove<Q:Eq+Hash+?Sized>(&mut self,key:&Q)->Option<V> where K:Borrow<Q> {
    let result=self.rows.remove(key);
    if result.is_some(){self.order.retain(|k|k.borrow()!=key);}
    result
  }
  pub fn get_mut<Q:Eq+Hash+?Sized>(&mut self,key:&Q)->Option<&mut V> where K:Borrow<Q> {self.rows.get_mut(key)}
  pub fn clear(&mut self) {self.rows.clear();self.order.clear();}
  pub fn retain(&mut self,mut keep:impl FnMut(&K,&mut V)->bool) {
    self.rows.retain(|k,v|keep(k,v));self.order.retain(|k|self.rows.contains_key(k));
  }
}
impl<K:Eq+Hash+Clone,V> Default for BoundedMap<K,V> {fn default()->Self {Self::new(4096)}}
impl<K,V> Deref for BoundedMap<K,V> {type Target=HashMap<K,V>;fn deref(&self)->&Self::Target {&self.rows}}
#[cfg(test)]
mod tests {
  use super::*;
  #[test]
  fn churn_is_bounded_and_eviction_releases_values() {
    let mut cache=BoundedMap::new(8);
    let value=std::sync::Arc::new(7);let weak=std::sync::Arc::downgrade(&value);
    cache.insert(0,value);for i in 1..10000 {cache.insert(i,std::sync::Arc::new(i));}
    assert_eq!(cache.len(),8);assert!(weak.upgrade().is_none());assert_eq!(**cache.get(&9999).unwrap(),9999);
    for _ in 0..100 {cache.insert(9999,std::sync::Arc::new(9999));}
    assert_eq!(cache.order.len(),8);
    cache.remove(&9999);cache.insert(10000,std::sync::Arc::new(10000));assert_eq!(cache.len(),8);
  }
}
